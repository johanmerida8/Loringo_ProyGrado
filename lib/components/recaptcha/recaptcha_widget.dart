// Conditional export: web implementation on Flutter web, stub everywhere else.
export 'recaptcha_stub.dart'
    if (dart.library.html) 'recaptcha_web.dart';
