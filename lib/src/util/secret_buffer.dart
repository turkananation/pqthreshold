/// Best-effort zeroization for sensitive byte buffers.
library;

import 'dart:typed_data';

import 'package:zeroize/zeroize.dart';
import 'package:swissarmyknife/swissarmyknife.dart';

/// Holds sensitive bytes and wipes them on [dispose].
///
/// Spec: `doc/SWISSARMYKNIFE.md` §3.4, `doc/SECURITY.md` §8.
final class SecretBuffer with Disposable {
  /// Creates a buffer that takes ownership of [bytes].
  SecretBuffer(Uint8List bytes) : _secret = SecretBytes.fromUint8List(bytes) {
    secureZero(bytes);
  }

  final SecretBytes _secret;

  /// A snapshot of the current material.
  ///
  /// The returned list is not the managed buffer and is not wiped by
  /// [dispose]. Callers handling sensitive material must dispose their own
  /// copy or keep it inside a `zeroize` container.
  Uint8List get bytes {
    ensureNotDisposed();
    return _secret.use(Uint8List.fromList);
  }

  @override
  void dispose() {
    if (!isDisposed) {
      _secret.dispose();
    }
    super.dispose();
  }
}
