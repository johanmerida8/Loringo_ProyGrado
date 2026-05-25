// ignore_for_file: equal_elements_in_set

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;

import 'moderation_terms.dart';

Future<String> getUploadFolder() async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    throw Exception('No user role found: user is not authenticated');
  }

  final uid = user.uid;

  final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

  final role = userDoc.data()?['role'] ?? 'user';

  print('User role: $role');

  if (role == 'admin') {
    return 'imagesPredefined';
  } else {
    return 'tasks/options/user_uploaded/$uid';
  }
}

class ImageService {
  final String cloudName = 'dsgovrpgp';
  final String uploadPreset = 'task_images';

  CollectionReference get imageCategories =>
      FirebaseFirestore.instance.collection('image_categories');

  Future<PlatformFile?> pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (res == null) return null;

    return res.files.first;
  }

  Future<List<PlatformFile>?> pickMultipleImages() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );

    if (res == null) return null;

    return res.files;
  }

  Future<bool> checkImageWithGoogleVision(Uint8List imageBytes) async {
    try {
      final apiKey = dotenv.env['GOOGLE_VISION_API_KEY'];
      if (apiKey == null) throw Exception('Missing GOOGLE_VISION_API_KEY');

      final base64Image = base64Encode(imageBytes);

      final requestBody = {
        'requests': [
          {
            'image': {'content': base64Image},
            'features': [
              {'type': 'SAFE_SEARCH_DETECTION'},
              {'type': 'LABEL_DETECTION', 'maxResults': 30},
              {'type': 'OBJECT_LOCALIZATION', 'maxResults': 30},
            ]
          }
        ]
      };

      final response = await http.post(
        Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        throw Exception('Google Vision API error: ${response.body}');
      }

      final result = jsonDecode(response.body);
      final visionResponse = result['responses'][0];

      // STRICT SafeSearch Detection
      final safeSearch = visionResponse['safeSearchAnnotation'] ?? {};

      final adult = safeSearch['adult'] ?? 'UNKNOWN';
      final violence = safeSearch['violence'] ?? 'UNKNOWN';
      final racy = safeSearch['racy'] ?? 'UNKNOWN';
      final medical = safeSearch['medical'] ?? 'UNKNOWN';
      final spoof = safeSearch['spoof'] ?? 'UNKNOWN';

      print('🔍 SafeSearch: adult=$adult, violence=$violence, racy=$racy, medical=$medical, spoof=$spoof');

      // Strict safety check - reject if LIKELY or VERY_LIKELY
      if (['LIKELY', 'VERY_LIKELY'].contains(adult) ||
          ['LIKELY', 'VERY_LIKELY'].contains(violence) ||
          ['LIKELY', 'VERY_LIKELY'].contains(racy) ||
          ['LIKELY', 'VERY_LIKELY'].contains(medical)) {
        print('❌ Blocked by strict SafeSearch');
        return false;
      }

      // Use predefined blocked terms for kid-safe content
      final blockedTerms = kidsafeModerationBlockedTerms;

      // Label Detection - Strict
      final labels = visionResponse['labelAnnotations'] ?? [];
      for (final label in labels) {
        final description = (label['description'] ?? '').toString().toLowerCase();
        final score = (label['score'] ?? 0).toDouble();

        print('Label: $description | score=$score');

        // STRICT: Lower threshold to 0.45 for high-confidence detection
        if (score >= 0.45 &&
            blockedTerms.any((term) => description.contains(term))) {
          print('❌ Blocked by label: $description (score: $score)');
          return false;
        }
      }

      // Object Localization - Strict
      final objects = visionResponse['localizedObjectAnnotations'] ?? [];
      for (final object in objects) {
        final name = (object['name'] ?? '').toString().toLowerCase();
        final score = (object['score'] ?? 0).toDouble();

        print('Object: $name | score=$score');

        // STRICT: Lower threshold to 0.40 for physical object detection
        if (score >= 0.40 &&
            blockedTerms.any((term) => name.contains(term))) {
          print('❌ Blocked by object: $name (score: $score)');
          return false;
        }
      }

      print('✅ Image passed all safety checks');
      return true;
    } catch (e) {
      print('❌ Error checking image with Google Vision: $e');
      return false;
    }
  }

  String _generateSignature(String timestamp, String folder) {
    final apiSecret = dotenv.env['CLOUDINARY_API_SECRET'];

    if (apiSecret == null) {
      throw Exception('Missing CLOUDINARY_API_SECRET');
    }

    final toSign =
        'folder=$folder&timestamp=$timestamp&upload_preset=$uploadPreset$apiSecret';

    return sha1.convert(utf8.encode(toSign)).toString();
  }

  Future<Map<String, dynamic>> uploadToCloudinary(
    PlatformFile file, {
    String? categoryName,
  }) async {
    final isSvg = file.name.toLowerCase().endsWith('.svg');
    final isPng = file.name.toLowerCase().endsWith('.png');

    if (file.bytes == null) {
      return {
        'success': false,
        'error': 'File bytes are empty',
      };
    }

    Uint8List fileBytes = file.bytes!;

    if (!isSvg) {
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          file.bytes!,
          quality: 80,
          format: isPng ? CompressFormat.png : CompressFormat.jpeg,
        );

        fileBytes = compressed;
      } catch (e) {
        print('Compression failed: $e, using original');
        fileBytes = file.bytes!;
      }
    }

    // Check with Google Vision API FIRST
    final isAppropriate = await checkImageWithGoogleVision(fileBytes);
    if (!isAppropriate) {
      return {
        'success': false,
        'error': 'Image rejected by Google Vision moderation',
        'reason': 'REJECT_INAPPROPRIATE_IMAGE',
      };
    }

    final folder = await getUploadFolder();
    final finalFolder = categoryName != null ? '$folder/$categoryName' : folder;

    final uri =
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

    final request = http.MultipartRequest('POST', uri);

    final timestamp =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final signature = _generateSignature(timestamp, finalFolder);
    final apiKey = dotenv.env['CLOUDINARY_API_KEY'];

    if (apiKey == null) {
      throw Exception('Missing CLOUDINARY_API_KEY');
    }

    request.fields['upload_preset'] = uploadPreset;
    request.fields['folder'] = finalFolder;
    request.fields['timestamp'] = timestamp;
    request.fields['signature'] = signature;
    request.fields['api_key'] = apiKey;

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: file.name,
      ),
    );

    final response = await request.send();
    final resStream = await http.Response.fromStream(response);

    if (response.statusCode != 200) {
      print('Cloudinary upload failed: ${resStream.body}');
      return {
        'success': false,
        'error': 'Upload failed',
        'details': resStream.body,
      };
    }

    final json = jsonDecode(resStream.body);

    print('✅ Image uploaded to Cloudinary successfully');
    print('Public ID: ${json['public_id']}');

    return {
      'success': true,
      'secure_url': json['secure_url'],
      'public_id': json['public_id'],
      'format': json['format'],
    };
  }

  Future<bool> deleteImage(String publicId) async {
    try {
      final apiKey = dotenv.env['CLOUDINARY_API_KEY'];
      final apiSecret = dotenv.env['CLOUDINARY_API_SECRET'];

      if (apiKey == null || apiSecret == null) {
        print('⚠️ Missing API credentials');
        return false;
      }

      final auth = base64Encode(utf8.encode('$apiKey:$apiSecret'));
      final headers = {
        'Authorization': 'Basic $auth',
        'Content-Type': 'application/x-www-form-urlencoded',
      };

      final uri = Uri.https(
        'api.cloudinary.com',
        '/v1_1/$cloudName/image/destroy',
      );

      final response = await http.delete(
        uri, 
        headers: headers,
        body: 'public_id=$publicId',
      );

      if (response.statusCode == 200) {
        print('✅ Image deleted: $publicId');
        return true;
      } else {
        print('❌ Failed to delete: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Error deleting image: $e');
      return false;
    }
  }

  Future<String> createCategory(String categoryName) async {
    try {
      final docRef = await imageCategories.add({
        'name': categoryName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('Category created with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('Error creating category: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final snapshot = await imageCategories
          .orderBy('createdAt', descending: false)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;

        return {
          'id': doc.id,
          'name': data['name'] as String? ?? '',
          ...data,
        };
      }).toList();
    } catch (e) {
      print('Error fetching categories: $e');
      return [];
    }
  }

  Future<String> saveImageMetadata({
    required String categoryId,
    required String name,
    required String imageUrl,
    required String cloudinaryPublicId,
    required String fileExtension,
  }) async {
    try {
      final isSvg = fileExtension.toLowerCase() == 'svg';

      String displayUrl = imageUrl;

      if (isSvg) {
        displayUrl = imageUrl.replaceFirst(
          '/upload/',
          '/upload/f_png,w_512,h_512,q_80/',
        );
      }

      final docRef = await imageCategories
          .doc(categoryId)
          .collection('images')
          .add({
        'name': name,
        'imageUrl': imageUrl,
        'displayUrl': displayUrl,
        'cloudinaryPublicId': cloudinaryPublicId,
        'format': isSvg ? 'svg' : 'image',

        // Auto-approved by Google Vision API before upload
        'moderationStatus': 'approved',
        'isVisible': true,

        'createdAt': FieldValue.serverTimestamp(),
      });

      print('✅ Image approved and saved: $name (ID: ${docRef.id})');
      return docRef.id;
    } catch (e) {
      print('Error saving image metadata: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getImagesByCategory(
    String categoryId, {
    bool onlyVisible = true,
  }) async {
    try {
      // Get all images without filtering by isVisible
      final snapshot = await imageCategories
          .doc(categoryId)
          .collection('images')
          .orderBy('name', descending: false)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'name': data['name'] as String? ?? '',
          'imageUrl': data['imageUrl'] as String? ?? '',
          'cloudinaryPublicId': data['cloudinaryPublicId'] as String? ?? '',
          ...data,
        };
      }).toList();
    } catch (e) {
      print('Error getting images by category: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getPendingImagesByCategory(
    String categoryId,
  ) async {
    try {
      final snapshot = await imageCategories
          .doc(categoryId)
          .collection('images')
          .where('moderationStatus', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();

        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
    } catch (e) {
      print('Error getting pending images: $e');
      return [];
    }
  }

  Future<void> approveImage({
    required String categoryId,
    required String imageId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    await imageCategories
        .doc(categoryId)
        .collection('images')
        .doc(imageId)
        .update({
      'moderationStatus': 'approved',
      'isVisible': true,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': user?.uid,
      'rejectedAt': null,
      'rejectedBy': null,
    });

    print('✅ Image approved: $imageId');
  }

  Future<void> rejectImage({
    required String categoryId,
    required String imageId,
    required String cloudinaryPublicId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    await deleteImage(cloudinaryPublicId);

    await imageCategories
        .doc(categoryId)
        .collection('images')
        .doc(imageId)
        .update({
      'moderationStatus': 'rejected',
      'isVisible': false,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedBy': user?.uid,
    });

    print('❌ Image rejected: $imageId');
  }

  Future<bool> deleteImageComplete(
    String categoryId,
    String imageId,
    String cloudinaryPublicId,
  ) async {
    try {
      final cloudinaryDeleted = await deleteImage(cloudinaryPublicId);

      if (cloudinaryDeleted) {
        await imageCategories
            .doc(categoryId)
            .collection('images')
            .doc(imageId)
            .delete();

        print('Image deleted from both Cloudinary and Firestore: $imageId');
        return true;
      } else {
        print('Failed to delete from Cloudinary, aborting Firestore deletion');
        return false;
      }
    } catch (e) {
      print('Error deleting image completely: $e');
      return false;
    }
  }
}