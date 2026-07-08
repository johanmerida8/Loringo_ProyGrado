// ignore_for_file: equal_elements_in_set

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:loringo_app/utils/moderation_terms.dart';
import 'package:permission_handler/permission_handler.dart';

// ── Upload folder resolver ────────────────────────────────────────────────────
Future<String> getUploadFolder() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('User is not authenticated');
  final doc = await FirebaseFirestore.instance
      .collection('users').doc(user.uid).get();
  final role = doc.data()?['role'] ?? 'user';
  return role == 'admin' ? 'imagesPredefined' : 'teacherUploads/${user.uid}';
}

// ── ImageService ──────────────────────────────────────────────────────────────
//
// Shared by BOTH teacher and admin upload flows. Any change here applies to
// both roles automatically — do not duplicate this logic in admin screens.

class ImageService {
  final String cloudName   = 'dmflzlyzk';
  final String uploadPreset = 'multimedia';

  // ── Permission helper ──────────────────────────────────────────────────
  // Solicita permiso de fotos según plataforma; true = listo para picker

  Future<bool> _requestStoragePermission() async {
    if (kIsWeb) return true;

    final Permission permission;
    if (defaultTargetPlatform == TargetPlatform.android) {
      permission = Permission.photos;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      permission = Permission.photos;
    } else {
      return true;
    }

    final status = await permission.status;

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    final result = await permission.request();
    return result.isGranted;
  }

  // ── File pickers ──────────────────────────────────────────────────────
  // Retornan null si el permiso fue denegado

  Future<PlatformFile?> pickImage() async {
    if (!await _requestStoragePermission()) return null;

    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'svg', 'webp'],
      withData: true,
    );
    return res?.files.first;
  }

  Future<List<PlatformFile>?> pickMultipleImages() async {
    if (!await _requestStoragePermission()) return null;

    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'svg', 'webp'],
      withData: true,
      allowMultiple: true,
    );
    return res?.files;
  }

  // ── Capa 1: filtro de nombre de archivo (rápido, no gasta llamada a la nube) ──
  // Atrapa casos obvios sin costo de red; NO reemplaza el análisis visual.

  bool checkImageNameForBlockedTerms(String fileName) {
    final lowerName = fileName.toLowerCase();
    final nameWithoutExt = lowerName.replaceAll(RegExp(r'\.[^.]*$'), '');
    final words = nameWithoutExt.split(RegExp(r'[_\s\-\.]+'));

    for (final word in words) {
      if (kidsafeModerationBlockedTerms.contains(word)) {
        // ignore: avoid_print
        print('[MODERATION] "$fileName" REJECTED at Capa 1 (filename) — matched word "$word"');
        return true;
      }
    }
    for (final term in kidsafeModerationBlockedTerms) {
      if (nameWithoutExt.contains(term)) {
        // ignore: avoid_print
        print('[MODERATION] "$fileName" REJECTED at Capa 1 (filename) — contains term "$term"');
        return true;
      }
    }
    return false;
  }

  // ── Capa 2: Google Cloud Vision SafeSearch, vía Cloud Function propia ────
  //
  // La API key de Vision NUNCA vive en el cliente — la llamada real ocurre
  // server-side en la función `moderateImage` (Firebase Functions), que
  // guarda la key como secret de Secret Manager. El cliente solo manda la
  // imagen en base64 y recibe {safe: true/false}.
  //
  // Solo VERY_LIKELY bloquea la subida del lado del servidor — LIKELY es
  // demasiado agresivo para contenido animado/ilustrado (partes del cuerpo,
  // frutas, personajes de caricatura), que es el dominio real de las
  // imágenes de Loringo.

  Future<bool> checkImageWithGoogleVision(Uint8List imageBytes) async {
    try {
      // ignore: avoid_print
      print('[MODERATION] Calling moderateImage — ${imageBytes.length} bytes');

      final callable = FirebaseFunctions.instance.httpsCallable('moderateImage');
      final result = await callable.call({
        'imageBase64': base64Encode(imageBytes),
      });

      final data = result.data as Map;
      // ignore: avoid_print
      print('[MODERATION] moderateImage raw response: $data');

      final isSafe = data['safe'] == true;
      // ignore: avoid_print
      print('[MODERATION] Capa 2 (Vision) decision: ${isSafe ? "SAFE ✅" : "REJECTED ❌ (reason: ${data['reason']})"}');

      return isSafe;
    } catch (e) {
      // ignore: avoid_print
      print('[MODERATION] moderateImage call FAILED (fail-closed → rejecting): $e');
      // Fail closed: cualquier error (red, función no desplegada, etc.)
      // rechaza la imagen en vez de dejarla pasar.
      return false;
    }
  }

  // ── Signature generation ──────────────────────────────────────────────────

  String _generateSignature(String timestamp, String folder) {
    final apiSecret = dotenv.env['CLOUDINARY_API_SECRET'];
    if (apiSecret == null) throw Exception('Missing CLOUDINARY_API_SECRET');
    final toSign =
        'folder=$folder&timestamp=$timestamp&upload_preset=$uploadPreset$apiSecret';
    return sha1.convert(utf8.encode(toSign)).toString();
  }

  // ── Cloudinary upload ─────────────────────────────────────────────────────
  //
  // Moderación en dos capas antes de subir a Cloudinary:
  //   1. Nombre de archivo (barato, atrapa lo obvio)
  //   2. Google Vision SafeSearch server-side (real, analiza el contenido)
  // SVG se salta la capa 2 porque es vectorial, no analizable por Vision.

  Future<Map<String, dynamic>> uploadToCloudinary(
    PlatformFile file, {
    String? categoryName,
  }) async {
    if (file.bytes == null) {
      return {'success': false, 'error': 'File bytes are empty'};
    }

    final fileName = file.name.toLowerCase();
    final isSvg  = fileName.endsWith('.svg');
    final isPng  = fileName.endsWith('.png');
    final isWebp = fileName.endsWith('.webp');

    if (!isSvg && !isPng && !isWebp) {
      return {
        'success': false,
        'error': 'Only PNG, SVG, and WebP formats are allowed',
        'reason': 'UNSUPPORTED_FILE_FORMAT',
      };
    }

    // Capa 1: nombre de archivo
    if (checkImageNameForBlockedTerms(file.name)) {
      return {
        'success': false,
        'error': 'Image name contains inappropriate content',
        'reason': 'REJECT_INAPPROPRIATE_IMAGE',
      };
    }

    Uint8List fileBytes = file.bytes!;
    if (isPng) {
      try {
        fileBytes = await FlutterImageCompress.compressWithList(
            file.bytes!, quality: 80, format: CompressFormat.png);
      } catch (_) {
        fileBytes = file.bytes!;
      }
    }
    // WebP no se comprime (igual que el original, solo comprimía PNG)

    // Capa 2: Google Vision SafeSearch server-side
    if (!isSvg) {
      if (!await checkImageWithGoogleVision(fileBytes)) {
        // ignore: avoid_print
        print('[MODERATION] "${file.name}" → FINAL: REJECTED (Capa 2 / Vision)');
        return {
          'success': false,
          'error': 'Image rejected by content moderation',
          'reason': 'REJECT_INAPPROPRIATE_IMAGE',
        };
      }
    }

    // ignore: avoid_print
    print('[MODERATION] "${file.name}" → FINAL: PASSED, uploading to Cloudinary...');

    final baseFolder  = await getUploadFolder();
    final finalFolder = categoryName != null ? '$baseFolder/$categoryName' : baseFolder;

    final apiKey = dotenv.env['CLOUDINARY_API_KEY'];
    if (apiKey == null) throw Exception('Missing CLOUDINARY_API_KEY');

    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final signature = _generateSignature(timestamp, finalFolder);

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
    )
      ..fields['upload_preset'] = uploadPreset
      ..fields['folder']        = finalFolder
      ..fields['timestamp']     = timestamp
      ..fields['signature']     = signature
      ..fields['api_key']       = apiKey
      ..files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: file.name));

    final response = await request.send();
    final body     = await http.Response.fromStream(response);

    if (response.statusCode != 200) {
      return {'success': false, 'error': 'Cloudinary upload failed', 'details': body.body};
    }

    final json = jsonDecode(body.body);
    return {
      'success':    true,
      'secure_url': json['secure_url'] as String,
      'public_id':  json['public_id']  as String,
      'format':     json['format']     as String,
    };
  }

  // ── Cloudinary delete ─────────────────────────────────────────────────────

  Future<bool> deleteImage(String publicId) async {
    try {
      final apiKey    = dotenv.env['CLOUDINARY_API_KEY'];
      final apiSecret = dotenv.env['CLOUDINARY_API_SECRET'];
      if (apiKey == null || apiSecret == null) return false;

      final response = await http.delete(
        Uri.https('api.cloudinary.com', '/v1_1/$cloudName/image/destroy'),
        headers: {
          'Authorization': 'Basic ${base64Encode(utf8.encode('$apiKey:$apiSecret'))}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'public_id=$publicId',
      );

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}