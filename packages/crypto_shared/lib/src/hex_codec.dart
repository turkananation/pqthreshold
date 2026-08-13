/// Hex helpers for ceremony IDs and PQTH blobs in JSON/API layers.
library;

import 'dart:typed_data';

/// Lowercase hex without `0x` prefix ([TEST_VECTORS.md](TEST_VECTORS.md) §3).
String bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Parses [hex] (even length) into bytes.
Uint8List hexToBytes(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('hex string must have even length');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Ceremony id as hex (32 chars).
String ceremonyIdToHex(Uint8List ceremonyId) => bytesToHex(ceremonyId);

/// Parses a 16-byte ceremony id from hex.
Uint8List ceremonyIdFromHex(String hex) {
  final bytes = hexToBytes(hex);
  if (bytes.length != 16) {
    throw FormatException('ceremony id must be 32 hex chars (16 bytes)');
  }
  return bytes;
}
