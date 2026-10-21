// ignore_for_file: equal_elements_in_set

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:loringo_app/utils/moderation_terms.dart';
import 'package:permission_handler/permission_handler.dart';

// ── ImageService ──────────────────────────────────────────────────────────────
//
// Shared by BOTH teacher and admin upload flows. Any change here applies to
// both roles automatically — do not duplicate this logic in admin screens.

class ImageService {
  // ── Avatar options (Cloudinary "avatars" folder) ──────────────────────
  //
  // Cached for the process lifetime — the folder's contents change rarely
  // (an admin/dev adding avatars), so every AvatarSelector open in a
  // session after the first is instant instead of re-hitting the network.
  static List<Map<String, String>>? _cachedAvatars;

  Future<List<Map<String, String>>> fetchAvatarOptions({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedAvatars != null) return _cachedAvatars!;

    final callable = FirebaseFunctions.instance.httpsCallable('listCloudinaryAvatars');
    final result = await callable.call();
    final data = result.data as Map;
    final list = (data['avatars'] as List).cast<Map>();
    final avatars = list
        .map((e) => {'publicId': e['publicId'] as String, 'url': e['url'] as String})
        .toList();

    _cachedAvatars = avatars;
    return avatars;
  }

  // ── Permission helper ──────────────────────────────────────────────────
  // Solicita permiso de fotos según plataforma; true = listo para picker
  //
  // Android 13+ (API 33+): Permission.photos → READ_MEDIA_IMAGES.
  // Android 12 o menor (API ≤ 32): ese permiso no existe, el equivalente es
  // Permission.storage → READ_EXTERNAL_STORAGE. Sin este respaldo el permiso
  // nunca se concedía en Android 11/12 y el selector no se abría.

  Future<bool> _requestStoragePermission() async {
    if (kIsWeb) return true;

    if (defaultTargetPlatform == TargetPlatform.android) {
      if (await Permission.photos.isGranted ||
          await Permission.photos.isLimited ||
          await Permission.storage.isGranted) {
        return true;
      }

      final photos = await Permission.photos.request();
      if (photos.isGranted || photos.isLimited) return true;

      // API ≤ 32: photos no aplica, se pide el permiso de almacenamiento.
      final storage = await Permission.storage.request();
      if (storage.isGranted) return true;

      if (photos.isPermanentlyDenied || storage.isPermanentlyDenied) {
        await openAppSettings();
      }
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final status = await Permission.photos.status;
      if (status.isGranted || status.isLimited) return true;

      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }

      final result = await Permission.photos.request();
      return result.isGranted || result.isLimited;
    }

    return true;
  }

  // ── File pickers ──────────────────────────────────────────────────────
  // Retornan null si el permiso fue denegado

  // SVG can't be analyzed by Google Vision, so the server only accepts it
  // from the admin image manager (see uploadModeratedImage.ts). Teacher
  // screens pass allowSvg: false so SVG isn't even offered to them.
  List<String> _allowedExtensions({required bool allowSvg}) =>
      allowSvg ? ['png', 'svg', 'webp'] : ['png', 'webp'];

  Future<PlatformFile?> pickImage({bool allowSvg = true}) async {
    if (!await _requestStoragePermission()) return null;

    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions(allowSvg: allowSvg),
      withData: true,
    );
    return res?.files.first;
  }

  Future<List<PlatformFile>?> pickMultipleImages({bool allowSvg = true}) async {
    if (!await _requestStoragePermission()) return null;

    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions(allowSvg: allowSvg),
      withData: true,
      allowMultiple: true,
    );
    return res?.files;
  }

  // ── Capa 1: filtro de nombre de archivo (rápido, no gasta llamada a la nube) ──
  // Atrapa casos obvios sin costo de red; NO reemplaza el análisis visual.

  bool checkImageNameForBlockedTerms(String fileName) {
    final lowerName = fileName.toLowerCase();
    // "drug deal" / "drug-deal" / "drug.deal" all become "drug_deal".
    final nameWithoutExt = lowerName
        .replaceAll(RegExp(r'\.[^.]*$'), '')
        .replaceAll(RegExp(r'[\s\-\.]+'), '_');
    final words = nameWithoutExt.split('_');

    for (final word in words) {
      if (kidsafeModerationBlockedWords.contains(word) ||
          kidsafeModerationBlockedTerms.contains(word)) {
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

  // ── Cloudinary upload (vía Cloud Function) ────────────────────────────────
  //
  // Moderación en dos capas antes de subir a Cloudinary:
  //   1. Nombre de archivo (aquí, barato, atrapa lo obvio)
  //   2. Google Vision SafeSearch + subida — ambas server-side en la función
  //      `uploadModeratedImage` (functions/src/uploadModeratedImage.ts).
  //
  // El cliente ya NO firma ni sube a Cloudinary: la API key/secret viven solo
  // como secrets de Cloud Functions, y la función solo sube si Vision aprueba
  // la imagen, así que la moderación no se puede saltar. La carpeta destino
  // (imagesPredefined vs teacherUploads/{uid}) también la decide el servidor
  // según el rol del usuario autenticado.
  // SVG es vectorial y Vision no lo analiza: solo lo acepta el servidor del
// gestor de imágenes (admin) y tras una revisión estructural (sin scripts).

  Future<Map<String, dynamic>> uploadToCloudinary(
    PlatformFile file, {
    String? categoryName,
    bool allowSvg = true,
    // false = ask the server to skip the Google Vision analysis (the
    // "Moderación automática" switch). The result's moderationApplied says
    // whether Vision actually analyzed the image.
    bool moderationEnabled = true,
  }) async {
    if (file.bytes == null) {
      return {'success': false, 'error': 'File bytes are empty'};
    }

    final fileName = file.name.toLowerCase();
    final isSvg  = fileName.endsWith('.svg');
    final isPng  = fileName.endsWith('.png');
    final isWebp = fileName.endsWith('.webp');

    if ((isSvg && !allowSvg) || (!isSvg && !isPng && !isWebp)) {
      return {
        'success': false,
        'error': allowSvg
            ? 'Only PNG, SVG, and WebP formats are allowed'
            : 'Only PNG and WebP formats are allowed',
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

    // Capa 2 + subida: server-side
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('uploadModeratedImage');
      final result = await callable.call({
        'imageBase64': base64Encode(fileBytes),
        'fileName': file.name,
        if (categoryName != null) 'categoryName': categoryName,
        if (!moderationEnabled) 'skipModeration': true,
      });
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        // ignore: avoid_print
        print('[MODERATION] "${file.name}" → FINAL: NOT UPLOADED (reason: ${data['reason']})');
        return {
          'success': false,
          'error': 'Image was not uploaded',
          'reason': data['reason'],
        };
      }

      // ignore: avoid_print
      print('[MODERATION] "${file.name}" → FINAL: PASSED and uploaded');
      return {
        'success':    true,
        'secure_url': data['secure_url'] as String,
        'public_id':  data['public_id']  as String,
        'format':     data['format']     as String,
        'moderationApplied': data['moderationApplied'] == true,
      };
    } catch (e) {
      // ignore: avoid_print
      print('[MODERATION] uploadModeratedImage call FAILED: $e');
      return {'success': false, 'error': 'Upload failed', 'details': '$e'};
    }
  }

  // ── Cloudinary delete ─────────────────────────────────────────────────────
  //
  // Routed through the `deleteCloudinaryImage` Cloud Function instead of
  // calling Cloudinary's destroy endpoint directly from the client (uploads
  // go server-side too now, via uploadModeratedImage). The admin "destroy"
  // endpoint is not CORS-enabled — a direct call from Flutter Web fails with a generic
  // "ClientException: Failed to fetch" (the browser blocking the
  // cross-origin request, not Cloudinary rejecting it). Going server-side
  // sidesteps CORS entirely and stops shipping CLOUDINARY_API_SECRET in the
  // compiled client bundle. See functions/src/deleteCloudinaryImage.ts.

  Future<bool> deleteImage(String publicId) async {
    if (publicId.isEmpty) {
      debugPrint('ImageService.deleteImage: empty publicId, nothing to delete');
      return false;
    }
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('deleteCloudinaryImage');
      final result = await callable.call({'publicId': publicId});
      final deleted = (result.data as Map)['deleted'] == true;
      if (!deleted) {
        debugPrint('ImageService.deleteImage: Cloud Function reported not-deleted for $publicId');
      }
      return deleted;
    } catch (e) {
      debugPrint('ImageService.deleteImage: error for $publicId: $e');
      return false;
    }
  }
}
