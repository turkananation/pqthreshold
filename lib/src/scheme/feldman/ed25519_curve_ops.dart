/// Ed25519 Edwards-curve point operations for Feldman VSS.
///
/// Adapted from `package:cryptography` (Apache-2.0) — pqforge lacks Ed25519 group
/// facades; see `doc/SCHEMES.md` §4 tier-2 fallback.
library;

import 'dart:typed_data';

import 'internal/ed25519_field.dart';

/// RFC 8032 Ed25519 group arithmetic on compressed 32-byte points.
abstract final class Ed25519CurveOps {
  /// Scalar multiplication with the Ed25519 base point.
  static Uint8List scalarBaseMult(Uint8List scalarLe32) {
    final s = Register25519()..setBytes(scalarLe32);
    return _pointCompress(_pointMul(s, Ed25519Point.base));
  }

  /// Scalar multiplication with an arbitrary point.
  static Uint8List scalarMult(Uint8List scalarLe32, Uint8List pointCompressed) {
    final point = _pointDecompress(pointCompressed);
    if (point == null) {
      throw ArgumentError('Invalid Ed25519 point encoding');
    }
    final s = Register25519()..setBytes(scalarLe32);
    return _pointCompress(_pointMul(s, point));
  }

  /// Point addition on compressed encodings.
  static Uint8List pointAdd(Uint8List left, Uint8List right) {
    final p = _pointDecompress(left);
    final q = _pointDecompress(right);
    if (p == null || q == null) {
      throw ArgumentError('Invalid Ed25519 point encoding');
    }
    final result = Ed25519Point.zero();
    _pointAdd(result, p, q);
    return _pointCompress(result);
  }

  /// Multi-scalar multiplication: sum(scalars[i] * points[i]).
  static Uint8List multiScalarMult(
    List<Uint8List> pointsCompressed,
    List<Uint8List> scalarsLe32,
  ) {
    if (pointsCompressed.length != scalarsLe32.length) {
      throw ArgumentError('points and scalars length mismatch');
    }
    var acc = Ed25519Point.zero();
    acc.y.data[0] = 1;
    acc.z.data[0] = 1;
    final tmp = Ed25519Point.zero();
    for (var i = 0; i < pointsCompressed.length; i++) {
      final point = _pointDecompress(pointsCompressed[i]);
      if (point == null) {
        throw ArgumentError('Invalid Ed25519 point at index $i');
      }
      final product = _pointMul(
        Register25519()..setBytes(scalarsLe32[i]),
        point,
      );
      _pointAdd(tmp, acc, product);
      acc = Ed25519Point(
        Register25519.from(tmp.x),
        Register25519.from(tmp.y),
        Register25519.from(tmp.z),
        Register25519.from(tmp.w),
      );
    }
    return _pointCompress(acc);
  }

  static void _pointAdd(
    Ed25519Point r,
    Ed25519Point p,
    Ed25519Point q, {
    Ed25519Point? tmp,
  }) {
    tmp ??= Ed25519Point.zero();

    final a = r.x;
    final b = r.y;
    final c = r.z;
    final d = r.w;

    final e = tmp.x;
    final f = tmp.y;
    final g = tmp.z;
    final h = tmp.w;

    a.sub(p.y, p.x);
    b.sub(q.y, q.x);
    a.mul(a, b);

    b.add(p.y, p.x);
    c.add(q.y, q.x);
    b.mul(b, c);

    c.mul(Register25519.two, p.w);
    c.mul(c, q.w);
    c.mul(c, Register25519.D);

    d.mul(Register25519.two, p.z);
    d.mul(d, q.z);

    e.sub(b, a);
    f.sub(d, c);
    g.add(d, c);
    h.add(b, a);

    a.mul(e, f);
    b.mul(g, h);
    c.mul(f, g);
    d.mul(e, h);
  }

  static Uint8List _pointCompress(Ed25519Point p) {
    final zInv = Register25519();
    final x = Register25519();
    final y = Register25519();

    zInv.pow(p.z, Register25519.PMinusTwo);
    x.mul(p.x, zInv);
    y.mul(p.y, zInv);

    y.data[15] |= (0x1 & x.data[0]) << 15;
    return y.toBytes(Uint8List(32));
  }

  static Ed25519Point? _pointDecompress(List<int> pointBytes) {
    if (pointBytes.length != 32) return null;
    final s = Uint8List.fromList(pointBytes);
    final sign = (0x80 & s[31]) >> 7;
    s[31] &= 0x7F;

    final y = Register25519()..setBytes(s);
    if (y.isGreaterOrEqual(Register25519.P)) return null;

    final v0 = Register25519();
    final v1 = Register25519();

    v0.mul(y, y);
    v0.sub(v0, Register25519.one);

    v1.mul(y, y);
    v1.mul(v1, Register25519.D);
    v1.add(v1, Register25519.one);
    v1.pow(v1, Register25519.PMinusTwo);

    final x2 = Register25519()..mul(v0, v1);

    if (x2.isZero) {
      if (sign == 1) return null;
      return Ed25519Point(
        Register25519.zero,
        y,
        Register25519.one,
        Register25519.zero,
      );
    }

    final x = v0;
    x.setBigInt(Register25519.PPlus3Slash8BigInt.toBigInt());
    x.pow(x2, x);

    v1.mul(x, x);
    v1.sub(v1, x2);
    if (!v1.isZero) {
      x.mul(x, Register25519.Z);
    }

    v1.mul(x, x);
    v1.sub(v1, x2);
    if (!v1.isZero) return null;

    if ((0x1 & x.data[0]) != sign) {
      x.sub(Register25519.P, x);
    }

    final xy = v1..mul(x, y);
    return Ed25519Point(x, y, Register25519.one, xy);
  }

  static Ed25519Point _pointMul(Register25519 s, Ed25519Point pointP) {
    var q = Ed25519Point.zero();
    q.y.data[0] = 1;
    q.z.data[0] = 1;

    pointP = Ed25519Point(
      Register25519.from(pointP.x),
      Register25519.from(pointP.y),
      Register25519.from(pointP.z),
      Register25519.from(pointP.w),
    );

    var tmp0 = Ed25519Point.zero();
    final tmp1 = Ed25519Point.zero();

    for (var i = 0; i < 256; i++) {
      final b = 0x1 & (s.data[i ~/ 16] >> (i % 16));
      if (b == 1) {
        _pointAdd(tmp0, q, pointP, tmp: tmp1);
        final oldQ = q;
        q = tmp0;
        tmp0 = oldQ;
      }
      _pointAdd(tmp0, pointP, pointP, tmp: tmp1);
      final oldP = pointP;
      pointP = tmp0;
      tmp0 = oldP;
    }
    return q;
  }
}
