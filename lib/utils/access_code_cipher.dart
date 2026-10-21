import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pointycastle/export.dart';

// ── AccessCodeCipher ─────────────────────────────────────────────────────────
//
// The student access code is static (set once at registration, never
// rotated) but must never sit in Firestore as plain, readable text. Unlike
// AccessCodeHasher's one-way HMAC (used only for the student-login lookup),
// this is reversible AES-256-GCM encryption keyed by a secret in .env
// (ACCESS_CODE_KEY) — so the parent can decrypt and view the original code
// again later, but reading the Firestore doc directly (a rules gap, a data
// export, a compromised device) exposes only ciphertext.

class AccessCodeCipher {
  static const _ivLength = 12; // GCM standard nonce size

  static Uint8List _key() {
    final keyBase64 = dotenv.env['ACCESS_CODE_KEY'];
    if (keyBase64 == null) throw Exception('Missing ACCESS_CODE_KEY');
    final key = base64Decode(keyBase64);
    if (key.length != 32) {
      throw Exception('ACCESS_CODE_KEY must decode to 32 bytes (AES-256)');
    }
    return key;
  }

  /// Returns "iv:ciphertext", both base64 — stored as-is in
  /// `accessCodeEncrypted`. A fresh random IV is used every call, so
  /// encrypting the same code twice yields different output.
  static String encrypt(String plaintext) {
    final iv = Uint8List.fromList(
      List.generate(_ivLength, (_) => Random.secure().nextInt(256)),
    );
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(_key()), 128, iv, Uint8List(0)));
    final ciphertext = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
    return '${base64Encode(iv)}:${base64Encode(ciphertext)}';
  }

  static String decrypt(String encoded) {
    final parts = encoded.split(':');
    if (parts.length != 2) throw Exception('Malformed encrypted access code');
    final iv = base64Decode(parts[0]);
    final ciphertext = base64Decode(parts[1]);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(_key()), 128, iv, Uint8List(0)));
    return utf8.decode(cipher.process(ciphertext));
  }
}
