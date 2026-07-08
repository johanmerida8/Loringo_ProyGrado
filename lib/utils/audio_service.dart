// // audio_service.dart

// // ignore_for_file: depend_on_referenced_packages

// import 'dart:convert';
// import 'dart:io';
// import 'dart:typed_data';

// import 'package:crypto/crypto.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:http/http.dart' as http;
// import 'package:path_provider/path_provider.dart';
// import 'package:record/record.dart';

// import 'package:loringo_app/services/speech_to_text/speech_permissions.dart';

// // ─── Upload folder resolver ───────────────────────────────────────────────────

// Future<String> getAudioUploadFolder() async {
//   final user = FirebaseAuth.instance.currentUser;
//   if (user == null) throw Exception('User is not authenticated');
//   return 'teacherUploads/${user.uid}/reading_audio';
// }

// // ─── AudioService ─────────────────────────────────────────────────────────────

// class AudioService {
//   final String cloudName = 'dmflzlyzk';

//   // NOTE: Ensure this upload preset is configured in Cloudinary to accept
//   // audio/video resource types (not image-only). Create a separate preset
//   // (e.g. 'task_audio') in your Cloudinary dashboard if needed.
//   final String uploadPreset = 'multimedia';

//   static const List<String> allowedExtensions = ['m4a', 'aac', 'mp3', 'opus'];
//   static const String defaultFormat = 'm4a';
//   static const int defaultBitRate = 128000;
//   static const int defaultSamplingRate = 44100;

//   static const double silenceThresholdDb = -35.0;
//   static const Duration silenceDuration = Duration(seconds: 3);

//   // ─── Recording ─────────────────────────────────────────────────────────────

//   final AudioRecorder _recorder = AudioRecorder();

//   Future<void> startRecording({
//     String? path,
//     int bitRate = defaultBitRate,
//     int samplingRate = defaultSamplingRate,
//   }) async {
//     if (!await SpeechPermissions.requestMicrophonePermission()) {
//       throw Exception('Microphone permission denied');
//     }

//     final recordPath = path ?? await _getTempAudioPath();

//     await _recorder.start(
//       RecordConfig(
//         encoder: AudioEncoder.aacLc,
//         bitRate: bitRate,
//         sampleRate: samplingRate,
//       ),
//       path: recordPath,
//     );
//   }

//   Future<String?> stopRecording() async {
//     return await _recorder.stop();
//   }

//   Future<bool> isRecording() async {
//     return await _recorder.isRecording();
//   }

//   Future<double> getAmplitude() async {
//     final amplitude = await _recorder.getAmplitude();
//     return amplitude?.current ?? 0.0;
//   }

//   bool isSignalTooQuiet(List<double> recentAmplitudes) {
//     if (recentAmplitudes.isEmpty) return false;
//     return recentAmplitudes.every((db) => db < silenceThresholdDb);
//   }

//   Future<bool> isMicrophonePermissionGranted() async {
//     return await SpeechPermissions.isMicrophonePermissionGranted();
//   }

//   void disposeRecorder() {
//     _recorder.dispose();
//   }

//   // ─── File path helpers ────────────────────────────────────────────────────

//   Future<String> _getTempAudioPath({String format = 'm4a'}) async {
//     final dir = await getTemporaryDirectory();
//     final timestamp = DateTime.now().millisecondsSinceEpoch;
//     return '${dir.path}/audio_$timestamp.$format';
//   }

//   Future<String> getTempAudioPathForPage(int pageIndex,
//       {String format = 'm4a'}) async {
//     final dir = await getTemporaryDirectory();
//     final timestamp = DateTime.now().millisecondsSinceEpoch;
//     return '${dir.path}/reading_page_${pageIndex}_$timestamp.$format';
//   }

//   // ─── File picker ──────────────────────────────────────────────────────────

//   Future<PlatformFile?> pickAudioFile() async {
//     final res = await FilePicker.platform.pickFiles(
//       type: FileType.custom,
//       allowedExtensions: allowedExtensions,
//       withData: true,
//     );
//     return res?.files.first;
//   }

//   Future<List<PlatformFile>?> pickMultipleAudioFiles() async {
//     final res = await FilePicker.platform.pickFiles(
//       type: FileType.custom,
//       allowedExtensions: allowedExtensions,
//       withData: true,
//       allowMultiple: true,
//     );
//     return res?.files;
//   }

//   // ─── Signature ────────────────────────────────────────────────────────────

//   // Cloudinary signed-upload signature. Parameters must be sorted
//   // alphabetically and must NOT include: file, api_key, resource_type,
//   // cloud_name, or the API secret itself.
//   String _generateSignature(String timestamp, String folder) {
//     final apiSecret = dotenv.env['CLOUDINARY_API_SECRET'];
//     if (apiSecret == null) throw Exception('Missing CLOUDINARY_API_SECRET');
//     final toSign =
//         'folder=$folder&timestamp=$timestamp&upload_preset=$uploadPreset$apiSecret';
//     return sha1.convert(utf8.encode(toSign)).toString();
//   }

//   // ─── Cloudinary upload ────────────────────────────────────────────────────

//   /// Upload audio bytes to Cloudinary.
//   ///
//   /// Uses the `/video/upload` endpoint — Cloudinary treats all audio files
//   /// (m4a, mp3, aac, opus) as video resources. The URL returned by Cloudinary
//   /// can be played by [just_audio]'s AudioPlayer directly.
//   ///
//   /// Returns: { success, secure_url, public_id, format, duration, bytes }
//   Future<Map<String, dynamic>> uploadAudio({
//     required Uint8List bytes,
//     required String fileName,
//     String? folder,
//     String? pageId,
//   }) async {
//     final extension = fileName.split('.').last.toLowerCase();
//     if (!allowedExtensions.contains(extension)) {
//       return {
//         'success': false,
//         'error': 'Unsupported format. Allowed: ${allowedExtensions.join(', ')}',
//         'reason': 'UNSUPPORTED_FORMAT',
//       };
//     }

//     final baseFolder = folder ?? await getAudioUploadFolder();
//     final finalFolder =
//         pageId != null ? '$baseFolder/$pageId' : baseFolder;

//     final apiKey = dotenv.env['CLOUDINARY_API_KEY'];
//     if (apiKey == null) throw Exception('Missing CLOUDINARY_API_KEY');

//     final timestamp =
//         (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
//     final signature = _generateSignature(timestamp, finalFolder);

//     // ─── FIX: Use /video/upload so Cloudinary accepts audio files ──────────
//     // The generic /upload endpoint defaults to image resource type and will
//     // reject or mis-classify audio. /video/upload handles m4a, mp3, aac, opus.
//     final request = http.MultipartRequest(
//       'POST',
//       Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/video/upload'),
//     )
//       ..fields['upload_preset'] = uploadPreset
//       ..fields['folder'] = finalFolder
//       ..fields['timestamp'] = timestamp
//       ..fields['signature'] = signature
//       ..fields['api_key'] = apiKey
//       // resource_type is now encoded in the URL — do NOT repeat it in fields
//       ..files.add(
//           http.MultipartFile.fromBytes('file', bytes, filename: fileName));

//     final response = await request.send();
//     final body = await http.Response.fromStream(response);

//     if (response.statusCode != 200) {
//       debugPrint('Cloudinary audio upload error: ${body.body}');
//       return {
//         'success': false,
//         'error': 'Cloudinary upload failed (${response.statusCode})',
//         'details': body.body,
//       };
//     }

//     final json = jsonDecode(body.body) as Map<String, dynamic>;
//     return {
//       'success': true,
//       'secure_url': json['secure_url'] as String,
//       'public_id': json['public_id'] as String,
//       'format': json['format'] as String? ?? extension,
//       'duration': json['duration'],
//       'bytes': json['bytes'],
//     };
//   }

//   /// Upload audio from a local file path (e.g. after recording).
//   /// Deletes the local temp file on successful upload.
//   Future<Map<String, dynamic>> uploadAudioFromPath({
//     required String path,
//     String? folder,
//     String? pageId,
//   }) async {
//     try {
//       final file = File(path);
//       if (!await file.exists()) {
//         return {'success': false, 'error': 'File does not exist: $path'};
//       }

//       final bytes = await file.readAsBytes();
//       final fileName = file.path.split('/').last;

//       final result = await uploadAudio(
//         bytes: bytes,
//         fileName: fileName,
//         folder: folder,
//         pageId: pageId,
//       );

//       if (result['success'] == true) {
//         try {
//           await file.delete();
//         } catch (_) {}
//       }

//       return result;
//     } catch (e) {
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   /// Upload audio from a FilePicker result.
//   Future<Map<String, dynamic>> uploadAudioFromFile({
//     required PlatformFile file,
//     String? folder,
//     String? pageId,
//   }) async {
//     if (file.bytes == null) {
//       return {'success': false, 'error': 'File bytes are empty'};
//     }
//     return uploadAudio(
//       bytes: file.bytes!,
//       fileName: file.name,
//       folder: folder,
//       pageId: pageId,
//     );
//   }

//   // ─── Cloudinary delete ────────────────────────────────────────────────────

//   Future<bool> deleteAudio(String publicId) async {
//     try {
//       final apiKey = dotenv.env['CLOUDINARY_API_KEY'];
//       final apiSecret = dotenv.env['CLOUDINARY_API_SECRET'];
//       if (apiKey == null || apiSecret == null) return false;

//       final response = await http.delete(
//         Uri.https(
//             'api.cloudinary.com', '/v1_1/$cloudName/video/destroy'),
//         headers: {
//           'Authorization':
//               'Basic ${base64Encode(utf8.encode('$apiKey:$apiSecret'))}',
//           'Content-Type': 'application/x-www-form-urlencoded',
//         },
//         body: 'public_id=$publicId',
//       );

//       return response.statusCode == 200;
//     } catch (_) {
//       return false;
//     }
//   }

//   // ─── Format helpers ───────────────────────────────────────────────────────

//   static String getFileExtension(String format) {
//     switch (format.toLowerCase()) {
//       case 'm4a':
//       case 'aac':
//         return '.m4a';
//       case 'mp3':
//         return '.mp3';
//       case 'opus':
//         return '.opus';
//       default:
//         return '.m4a';
//     }
//   }

//   static String getMimeType(String format) {
//     switch (format.toLowerCase()) {
//       case 'm4a':
//       case 'aac':
//         return 'audio/mp4';
//       case 'mp3':
//         return 'audio/mpeg';
//       case 'opus':
//         return 'audio/opus';
//       default:
//         return 'audio/mp4';
//     }
//   }

//   /// Estimated file size per minute at given bitrate (KB).
//   static int estimateFileSizePerMinute(int bitRate) {
//     return (bitRate * 60 / 8 / 1024).round();
//   }

//   static String formatFileSize(int bytes) {
//     if (bytes < 1024) return '$bytes B';
//     if (bytes < 1024 * 1024) {
//       return '${(bytes / 1024).toStringAsFixed(1)} KB';
//     }
//     return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
//   }
// }

// // ─── AudioPlayerService (placeholder) ────────────────────────────────────────

// class AudioPlayerService {
//   Future<void> playUrl(String url) async {
//     // TODO: Use audioplayers or just_audio
//   }

//   Future<void> stop() async {}

//   Future<void> pause() async {}

//   Future<void> resume() async {}

//   void dispose() {}
// }