import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ── AccessCodeHasher ─────────────────────────────────────────────────────────
//
// Student access codes are never stored in plaintext (see database.dart's
// STUDENTS section) — only their HMAC-SHA256 hash is persisted. HMAC (keyed
// with a pepper from .env, same secret-loading pattern as
// CLOUDINARY_API_SECRET in image_service.dart) is used instead of a plain
// hash because the code's keyspace is small (33 symbols^6 ≈ 1.29B
// combinations) and fully precomputable into a rainbow table offline; the
// pepper makes that precomputation infeasible without also having the key.

class AccessCodeHasher {
  static const _chars =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No O, 0, I, 1 to avoid confusion

  /// Cryptographically secure 6-character access code.
  static String generateCode() {
    final random = Random.secure();
    return List.generate(
      6,
      (_) => _chars[random.nextInt(_chars.length)],
    ).join();
  }

  static String hash(String code) {
    final pepper = dotenv.env['ACCESS_CODE_PEPPER'];
    if (pepper == null) throw Exception('Missing ACCESS_CODE_PEPPER');
    final hmac = Hmac(sha256, utf8.encode(pepper));
    return hmac.convert(utf8.encode(code.trim().toUpperCase())).toString();
  }
}
