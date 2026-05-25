import 'package:cloudinary_flutter/cloudinary_context.dart';
import 'package:cloudinary_url_gen/cloudinary.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:loringo_app/firebase_options.dart';
import 'package:loringo_app/screens/initials/splash_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
// import 'package:webview_flutter_plus/webview_flutter_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  // ignore: deprecated_member_use
  CloudinaryContext.cloudinary =
      Cloudinary.fromCloudName(cloudName: dotenv.env['CLOUDINARY_CLOUD_NAME']!);
  

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Loringo App',
      home: kIsWeb ? const AuthGate() : SplashScreen(),
    );
  }
}
