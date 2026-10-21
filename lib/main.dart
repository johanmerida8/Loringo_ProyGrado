import 'package:cloudinary_flutter/cloudinary_context.dart';
import 'package:cloudinary_url_gen/cloudinary.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:loringo_app/firebase_options.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:loringo_app/screens/initials/splash_screen.dart';
import 'package:loringo_app/services/audio/feedback_sound_service.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/notifications/one_signal_service.dart';
import 'package:loringo_app/utils/app_route_observer.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

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
      if (kDebugMode) {
        OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
        print('   OneSignal initialized for mobile');
      }
    } else {
      if (kDebugMode) {
        print('   OneSignal App ID not found in .env file');
      }
    }
  } else {
    if (kDebugMode) {
      print('   OneSignal skipped on web platform');
    }
  }

  final notificationProvider = NotificationProvider();

  // Single place that detaches OneSignal on logout. There are several
  // independent signOut() call sites (LogoutService, profile screens,
  // biometric/splash fallbacks...), so instead of patching each one this
  // listens for the signed-in -> signed-out transition. OneSignal.logout()
  // only clears the external user id -- the device's push subscription
  // stays opted in, so the next account's OneSignal.login() (AuthGate)
  // re-targets the same subscription instead of creating a new one.
  String? previousUid;
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (previousUid != null && user == null) {
      OneSignalNotificationService.removeUser();
      notificationProvider.reset();
    }
    previousUid = user?.uid;
  });

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('es')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      // false: no manual language toggle anymore — always re-detect the
      // live device locale on every launch instead of freezing on
      // whatever was picked once and persisting it.
      saveLocale: false,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BiometricProvider()),
          ChangeNotifierProvider.value(value: notificationProvider),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ],
        child: const MyApp(),
      ),
    ),
  );

  // loads the success/fail sounds once so the first
  // feedback sound a student hears in any task screen is instant instead
  // of paying the setAsset load cost.
  FeedbackSoundService.instance.preload();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Loringo',
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      navigatorObservers: [appRouteObserver],
      home: kIsWeb ? const AuthGate() : const SplashScreen(),
    );
  }
}