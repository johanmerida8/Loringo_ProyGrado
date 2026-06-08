import 'package:cloudinary_flutter/cloudinary_context.dart';
import 'package:cloudinary_url_gen/cloudinary.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:loringo_app/firebase_options.dart';
import 'package:loringo_app/screens/initials/splash_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  // ignore: deprecated_member_use
  CloudinaryContext.cloudinary =
      Cloudinary.fromCloudName(cloudName: dotenv.env['CLOUDINARY_CLOUD_NAME']!);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Only initialize OneSignal on mobile platforms (not web)
  if (!kIsWeb) {
    final oneSignalAppId = dotenv.env['ONESIGNAL_APP_ID'];
    if (oneSignalAppId != null && oneSignalAppId.isNotEmpty) {
      await OneSignal.initialize(oneSignalAppId);
      await OneSignal.Notifications.requestPermission(true);
      if (kDebugMode) {
        OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
        print('✅ OneSignal initialized for mobile');
      }
    } else {
      if (kDebugMode) {
        print('⚠️ OneSignal App ID not found in .env file');
      }
    }
  } else {
    if (kDebugMode) {
      print('⚠️ OneSignal skipped on web platform');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Loringo App',
      home: kIsWeb ? const AuthGate() : const SplashScreen(),
    );
  }
}