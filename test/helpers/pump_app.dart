import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads assets/translations/<locale>.json straight off disk instead of
/// through `rootBundle`. `RootBundleAssetLoader` (easy_localization's
/// default) calls `rootBundle.loadString`, which — only when awaited from
/// inside a [LocalizationsDelegate.load] call during `pumpWidget` (i.e.
/// inside Flutter's BuildOwner.buildScope) — never resolves on this
/// Flutter SDK (3.44.6): the `Localizations` widget stays on its
/// `SizedBox.shrink()` "still loading" placeholder forever, hanging
/// `pumpAndSettle()`. Reading the file with `dart:io` instead of
/// `rootBundle` sidesteps that platform-channel round trip entirely.
///
/// IMPORTANT: this must return a plain `Future.value(data)`, NOT a
/// `SynchronousFuture`. `easy_localization`'s
/// `EasyLocalizationController._combineAssetLoaders` collects every
/// loader's future into a list and awaits them with `Future.wait(...)`.
/// When every future in that list is a `SynchronousFuture` (completes
/// during the SAME synchronous call that creates it, before `Future.wait`
/// finishes registering its own internal completion bookkeeping),
/// `Future.wait` resolves with an EMPTY result list instead of the real
/// values — a genuine synchronous-reentrancy edge case in how `Future
/// .wait` composes already-completed futures, confirmed by instrumenting
/// the package: the loader is called and parses the JSON correctly, but
/// `Future.wait`'s callback still receives 0 results. The translations
/// map then stays empty and every `.tr()` call silently returns the raw
/// key for the rest of the test — no exception, no warning beyond an
/// easy_localization "key not found" log easy to miss. Wrapping the same
/// synchronously-read data in a normal `Future.value(...)` (one real
/// microtask, not a `SynchronousFuture`) avoids that race while still
/// resolving fast enough that `pumpAndSettle()` never hangs.
class _SyncFileAssetLoader extends AssetLoader {
  const _SyncFileAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) {
    final file = File('$path/${locale.languageCode}.json');
    final data = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    return Future.value(data);
  }
}

/// Wraps [child] the same way lib/main.dart wraps the real app: the real
/// EasyLocalization widget (loading the real assets/translations/*.json —
/// already registered in pubspec.yaml, so this works under plain
/// `flutter test` with no extra setup) + MaterialApp + the real
/// MultiProvider set (BiometricProvider, NotificationProvider,
/// LocaleProvider), so widget tests of translated screens see real
/// resolved text instead of raw `.tr()` keys (which are long enough to
/// overflow some layouts and never match a test's `find.text('...')`
/// assertion against real English copy) and don't crash for lack of an
/// ancestor provider. None of the three providers do any work at
/// construction time (LocaleProvider's constructor is context-free by
/// design; the other two only act once .initialize(userId) is called), so
/// this carries no platform-channel/Firebase risk. `saveLocale: false`
/// keeps each test run isolated from whatever locale a previous test (or
/// a real device) last saved.
///
/// EasyLocalization's controller unconditionally awaits
/// SharedPreferences.getInstance() during init (regardless of
/// saveLocale), which hangs forever in a widget test with no mock
/// handler registered for that platform channel. Establishing the mock
/// here — before EasyLocalization touches it — means test files no
/// longer need their own setUpMockSharedPreferences() call just to use a
/// translated screen; nothing in this suite relies on non-default
/// (non-empty) seeded values, so overwriting with `{}` here is safe even
/// for files that also call it themselves.
Future<void> pumpApp(WidgetTester tester, Widget child) async {
  final originalSize = tester.view.physicalSize;
  final originalRatio = tester.view.devicePixelRatio;
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.physicalSize = originalSize;
    tester.view.devicePixelRatio = originalRatio;
  });

  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();

  Widget buildTree() => EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('es')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        saveLocale: false,
        assetLoader: const _SyncFileAssetLoader(),
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => BiometricProvider()),
            ChangeNotifierProvider(create: (_) => NotificationProvider()),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ],
          child: Builder(
            builder: (context) => MaterialApp(
              debugShowCheckedModeBanner: false,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: child,
            ),
          ),
        ),
      );

  // First pump: even with the synchronous asset loader above, easy_localization's
  // own delegate.load() is declared `async`, so Dart still defers its result by
  // at least one microtask — the very first frame's `.tr()` calls resolve against
  // an empty Localization.instance and render raw keys. Because `child` is the
  // same widget instance/const value both times, Flutter's element diffing would
  // otherwise skip rebuilding it once translations finish loading (identical
  // widget → no rebuild), so the raw-key frame would never self-correct like it
  // does in the real app (which defers showing any frame at all until this
  // settles). Settling once lets the translations finish loading into the global
  // Localization.instance singleton...
  await tester.pumpWidget(buildTree());
  await tester.pumpAndSettle();
  // ...then pumping a brand new element tree forces every widget (including
  // `child`) to actually build for the first time against that now-populated
  // singleton, so `.tr()` returns real text from this point on.
  await tester.pumpWidget(buildTree());
  await tester.pumpAndSettle();
}
