/// Best-effort zeroization for sensitive byte buffers.
library;

import 'dart:typed_data';

import 'package:swissarmyknife/swissarmyknife.dart';

/// Holds sensitive bytes and wipes them on [dispose].
///
/// Spec: `doc/SWISSARMYKNIFE.md` §3.4, `doc/SECURITY.md` §8.
final class SecretBuffer with Disposable {
  /// Creates a buffer that takes ownership of [bytes].
  SecretBuffer(this._bytes);

  Uint8List _bytes;

  /// Current material (do not retain references after [dispose]).
  Uint8List get bytes {
    ensureNotDisposed();
    return _bytes;
  }

  @override
  void dispose() {
    if (!isDisposed) {
      for (var i = 0; i < _bytes.length; i++) {
        _bytes[i] = 0;
      }
      _bytes = Uint8List(0);
    }
    super.dispose();
  }
}
