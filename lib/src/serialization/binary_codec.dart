/// Big-endian primitive read/write for PQTH payloads.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../errors/threshold_exception.dart';

/// Cursor over a fixed byte buffer with bounds-checked reads.
@internal
final class BinaryReader {
  BinaryReader(this._data, [this._offset = 0]);

  final Uint8List _data;
  int _offset;

  /// Bytes remaining.
  int get remaining => _data.length - _offset;

  /// Current cursor position.
  int get offset => _offset;

  void _require(int length) {
    if (_offset + length > _data.length) {
      throw SerializationError(
        'Unexpected end of buffer (need $length bytes, have $remaining)',
      );
    }
  }

  /// Reads exactly [length] bytes.
  Uint8List readBytes(int length) {
    _require(length);
    final slice = Uint8List.sublistView(_data, _offset, _offset + length);
    _offset += length;
    return slice;
  }

  /// Reads one unsigned byte.
  int readUint8() {
    _require(1);
    return _data[_offset++];
  }

  /// Reads big-endian uint16.
  int readUint16Be() {
    _require(2);
    final value = _data.buffer.asByteData(_data.offsetInBytes + _offset).getUint16(
          0,
          Endian.big,
        );
    _offset += 2;
    return value;
  }

  /// Reads big-endian uint32.
  int readUint32Be() {
    _require(4);
    final value = _data.buffer.asByteData(_data.offsetInBytes + _offset).getUint32(
          0,
          Endian.big,
        );
    _offset += 4;
    return value;
  }

  /// Reads big-endian uint64 (via [PqBytes.readUint64]).
  int readUint64Be() {
    _require(8);
    final value = PqBytes.readUint64(_data, _offset);
    _offset += 8;
    return value;
  }

  /// Ensures the entire buffer was consumed.
  void expectEnd() {
    if (_offset != _data.length) {
      throw SerializationError(
        'Trailing bytes after parse (${_data.length - _offset} remaining)',
      );
    }
  }
}

/// Append-only big-endian writer.
@internal
final class BinaryWriter {
  final _chunks = <Uint8List>[];

  /// Encoded length so far.
  int get length => _chunks.fold<int>(0, (sum, c) => sum + c.length);

  void writeBytes(Uint8List bytes) {
    _chunks.add(bytes);
  }

  void writeUint8(int value) {
    RangeError.checkValueInInterval(value, 0, 0xFF, 'value');
    _chunks.add(Uint8List.fromList([value]));
  }

  void writeUint16Be(int value) {
    RangeError.checkValueInInterval(value, 0, 0xFFFF, 'value');
    final out = Uint8List(2);
    out.buffer.asByteData().setUint16(0, value, Endian.big);
    _chunks.add(out);
  }

  void writeUint32Be(int value) {
    RangeError.checkValueInInterval(value, 0, 0xFFFFFFFF, 'value');
    _chunks.add(PqBytes.uint32(value));
  }

  void writeUint64Be(int value) {
    _chunks.add(PqBytes.uint64(value));
  }

  /// Returns concatenated bytes.
  Uint8List toBytes() => PqBytes.concat(_chunks);
}
