// ignore_for_file: equal_elements_in_set

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
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

class ImageService {
  final String cloudName   = 'dmflzlyzk';
  final String uploadPreset = 'task_images';

  // ── Permission helper ─────────────────────────────────────────────────────
  // Web: permissions are handled by the browser — no runtime request needed.
  // Android 13+ (API 33): READ_MEDIA_IMAGES covers photo access.
  // Android 12 and below: READ_EXTERNAL_STORAGE is the equivalent.
  // iOS: NSPhotoLibraryUsageDescription in Info.plist + runtime request.
  //
  // Returns:
  //   true  → permission granted, proceed with file picker
  //   false → permission denied or permanently denied; caller should stop

  Future<bool> _requestStoragePermission() async {
    // Web has no permission API — browser handles it natively
    if (kIsWeb) return true;

    // Determine the right permission for this Android version / platform
    final Permission permission;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android 13+ uses READ_MEDIA_IMAGES; older uses READ_EXTERNAL_STORAGE.
      // permission_handler selects the correct one automatically via photos.
      permission = Permission.photos;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      permission = Permission.photos;
    } else {
      // Desktop (macOS, Linux, Windows) — no runtime permission needed
      return true;
    }

    final status = await permission.status;

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      // User has tapped "Never ask again" — send them to app settings
      await openAppSettings();
      return false;
    }

    // First time or previously denied — show the system permission dialog
    final result = await permission.request();
    return result.isGranted;
  }

  // ── File pickers ──────────────────────────────────────────────────────────
  // Both methods request storage permission before opening the file picker.
  // If permission is denied, they return null so the caller can handle it
  // (show a message, do nothing) without crashing.

  Future<PlatformFile?> pickImage() async {
    if (!await _requestStoragePermission()) return null;

    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'svg'],
      withData: true,
    );
    return res?.files.first;
  }

  Future<List<PlatformFile>?> pickMultipleImages() async {
    if (!await _requestStoragePermission()) return null;

    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'svg'],
      withData: true,
      allowMultiple: true,
    );
    return res?.files;
  }

  // ── Google Vision SafeSearch moderation ───────────────────────────────────
  // Only VERY_LIKELY blocks the upload — LIKELY is too aggressive for
  // cartoon/illustration content (body parts, fruits, characters).

  Future<bool> checkImageWithGoogleVision(Uint8List imageBytes) async {
    try {
      final apiKey = dotenv.env['GOOGLE_VISION_API_KEY'];
      if (apiKey == null) throw Exception('Missing GOOGLE_VISION_API_KEY');

      final response = await http.post(
        Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requests': [{
            'image': {'content': base64Encode(imageBytes)},
            'features': [{'type': 'SAFE_SEARCH_DETECTION'}],
          }],
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Vision API HTTP ${response.statusCode}');
      }

      final visionResponse = (jsonDecode(response.body) as Map)['responses'][0];
      final safeSearch = visionResponse['safeSearchAnnotation'] as Map? ?? {};

      for (final key in ['adult', 'violence', 'racy']) {
        final rating = safeSearch[key] as String? ?? 'UNKNOWN';
        if (rating == 'VERY_LIKELY') return false;
      }

      return true;
    } catch (_) {
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

  Future<Map<String, dynamic>> uploadToCloudinary(
    PlatformFile file, {
    String? categoryName,
  }) async {
    if (file.bytes == null) {
      return {'success': false, 'error': 'File bytes are empty'};
    }

    final fileName = file.name.toLowerCase();
    final isSvg = fileName.endsWith('.svg');
    final isPng = fileName.endsWith('.png');

    if (!isSvg && !isPng) {
      return {
        'success': false,
        'error': 'Only PNG and SVG formats are allowed',
        'reason': 'UNSUPPORTED_FILE_FORMAT',
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

    if (!await checkImageWithGoogleVision(fileBytes)) {
      return {
        'success': false,
        'error': 'Image rejected by content moderation',
        'reason': 'REJECT_INAPPROPRIATE_IMAGE',
      };
    }

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