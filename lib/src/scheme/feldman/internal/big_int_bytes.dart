library;

import 'dart:typed_data';

final _byteMask = BigInt.from(255);

/// Converts bytes to [BigInt]. Uses little-endian byte order.
BigInt bigIntFromBytes(List<int> bytes) {
  var result = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    result = (result << 8) + BigInt.from(bytes[i]);
  }
  return result;
}

/// Converts [BigInt] to bytes. Uses little-endian byte order.
Uint8List bigIntToBytes(BigInt? value, List<int> result,
    [int start = 0, int? length]) {
  final original = value;
  length ??= result.length - start;
  for (var i = 0; i < length; i++) {
    result[start + i] = (_byteMask & value!).toInt();
    value >>= 8;
  }
  if (value != BigInt.zero) {
    throw ArgumentError.value(original);
  }
  return result as Uint8List;
}
