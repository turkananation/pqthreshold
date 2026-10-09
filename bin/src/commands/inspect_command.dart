/// `inspect` — describe PQTH artifacts without decrypting secrets.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/src/serialization/pqth_format.dart';
import 'package:pqthreshold/src/serialization/pqth_kind.dart';

import '../console.dart';
import '../support.dart';

/// Describes `.pqth` files and pqforge-compatible wrapped share JSON.
final class InspectCommand extends Command<void> {
  InspectCommand() {
    argParser.addOption(
      'in',
      mandatory: true,
      valueHelp: 'file',
      help: 'A .pqth object, ceremony.id (16 bytes), or wrapped share JSON.',
    );
  }

  @override
  String get name => 'inspect';

  @override
  String get description =>
      'Show PQTH header, params, or wrapped-key metadata (no decrypt).';

  @override
  String get usageFooter => usageExamples([
    'pqthreshold inspect --in ceremony/params.pqth',
    'pqthreshold inspect --in officers/alice.share.wrapped.json',
    'pqthreshold inspect --in ceremony/ceremony.id',
  ]);

  @override
  Future<void> run() async {
    try {
      final path = argResults!['in'] as String;
      final bytes = await readBytes(path);

      if (_tryInspectPqth(bytes)) return;
      if (_tryInspectCeremonyId(bytes)) return;
      if (await _tryInspectWrappedJson(path)) return;

      throw FormatException(
        'Not a recognized pqthreshold artifact (expected PQTH magic, '
        '16-byte ceremony id, or wrapped JSON)',
      );
    } on Object catch (error) {
      handleCliError(error);
    }
  }

  bool _tryInspectPqth(List<int> bytes) {
    if (bytes.length < pqthMagicBytes.length) return false;
    for (var i = 0; i < pqthMagicBytes.length; i++) {
      if (bytes[i] != pqthMagicBytes[i]) return false;
    }

    final header = PqthHeader.decode(Uint8List.fromList(bytes));
    console.section('PQTH object');
    console.detail('format', 'PQTH v${header.version}');
    console.detail('kind', kindDisplayName(header.kind));
    console.detail('scheme', schemeDisplayName(header.scheme));
    console.detail('total size', '${bytes.length} bytes');

    if (header.kind == PqthObjectKind.thresholdParams) {
      if (bytes.length != thresholdParamsEncodedLength) {
        console.warn(
          'expected $thresholdParamsEncodedLength bytes for ThresholdParams, '
          'got ${bytes.length}',
        );
      } else {
        final params = ThresholdParams.fromBytes(Uint8List.fromList(bytes));
        console.section('ThresholdParams');
        printThresholdParams(params);
      }
      return true;
    }

    console.hint(
      'Full payload decode for ${kindDisplayName(header.kind)} ships in a '
      'later phase — header only for now.',
    );
    return true;
  }

  bool _tryInspectCeremonyId(List<int> bytes) {
    if (bytes.length != 16) return false;
    try {
      validateCeremonyId(Uint8List.fromList(bytes));
    } on ThresholdException {
      return false;
    }
    console.section('Ceremony ID');
    console.detail('length', '16 bytes');
    console.detail('hex', bytesToHex(Uint8List.fromList(bytes)));
    console.detail('all-zero', 'no');
    return true;
  }

  Future<bool> _tryInspectWrappedJson(String path) async {
    if (!path.endsWith('.json')) return false;
    final text = await File(path).readAsString();
    if (!text.trim().startsWith('{')) return false;

    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) return false;

    if (json.containsKey('ciphertext') && json.containsKey('kdf')) {
      console.section('Wrapped secret (pqforge PqWrappedKey envelope)');
      console.detail('kind', '${json['keyKind'] ?? 'unknown'}');
      console.detail('algorithm', '${json['algorithmId'] ?? 'unknown'}');
      if (json['keyId'] is String) {
        console.detail('key id', '${json['keyId']}');
      }
      console.detail('kdf', '${json['kdf'] ?? 'unknown'}');
      console.hint(
        'Passphrase unwrap is not performed by inspect — same as pqforge inspect.',
      );
      return true;
    }

    return false;
  }
}
