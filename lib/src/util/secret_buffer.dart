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

  /// A read-only window onto the managed material.
  ///
  /// Prefer this over [bytes]. The buffer handed to [fn] is the managed
  /// backing store, not a copy: [dispose] wipes it, and no untracked plaintext
  /// copy escapes into the caller's scope.
  ///
  /// **Do not retain the buffer beyond [fn].** Retaining it defeats the
  /// disposal guarantee.
  ///
  /// Throws [StateError] after [dispose].
  T use<T>(T Function(Uint8List bytes) fn) {
    ensureNotDisposed();
    return _secret.use(fn);
  }

  /// A read/write window onto the managed material.
  ///
  /// For in-place transforms. Same retention warning as [use].
  ///
  /// Throws [StateError] after [dispose].
  T mutate<T>(T Function(Uint8List bytes) fn) {
    ensureNotDisposed();
    return _secret.mutate(fn);
  }

  /// A snapshot of the current material.
  ///
  /// The returned list is **not** the managed buffer and is not wiped by
  /// [dispose]. Callers handling sensitive material must wipe their own copy
  /// with `package:zeroize`'s `secureZero`, or keep it inside a `SecretBytes`.
  ///
  /// Prefer [use] or [mutate]: this getter exists for APIs that require a
  /// bare `Uint8List`, and each call is one more copy the caller must track.
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
