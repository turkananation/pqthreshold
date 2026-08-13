/// SHA-512 helper for FROST protocol hashes.
///
/// pqforge exposes SHA-256 via [PqBytes.sha256] but has no SHA-512 facade.
/// Uses pointycastle (transitive via pqforge) per `doc/SCHEMES.md` §4 tier-2.
library;

import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:pointycastle/digests/sha512.dart';

/// Returns SHA-512 digest of [input] (64 bytes).
Uint8List sha512Bytes(Uint8List input) {
  final digest = SHA512Digest()..update(input, 0, input.length);
  final out = Uint8List(64);
  digest.doFinal(out, 0);
  return out;
}
