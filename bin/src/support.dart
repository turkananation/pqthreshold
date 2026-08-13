/// Shared helpers for the pqthreshold CLI.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/src/serialization/pqth_kind.dart';

import 'console.dart';

/// CLI names for [SchemeId].
const Map<String, SchemeId> schemeIdsByCliName = {
  'frost-ed25519-v1': SchemeId.frostEd25519V1,
  'frostEd25519V1': SchemeId.frostEd25519V1,
};

/// Human-readable scheme label for inspect output.
String schemeDisplayName(SchemeId scheme) => switch (scheme) {
      SchemeId.frostEd25519V1 => 'FROST Ed25519 v1',
    };

/// Kind label for inspect output.
String kindDisplayName(PqthObjectKind kind) => switch (kind) {
      PqthObjectKind.thresholdParams => 'ThresholdParams',
      PqthObjectKind.share => 'Share',
      PqthObjectKind.publicKey => 'PublicKey',
      PqthObjectKind.partialSignature => 'PartialSignature',
      PqthObjectKind.transcript => 'Transcript',
      PqthObjectKind.continuityProof => 'ContinuityProof',
    };

void addSchemeOption(ArgParser parser) {
  parser.addOption(
    'scheme',
    defaultsTo: 'frost-ed25519-v1',
    allowed: schemeIdsByCliName.keys.toList(),
    help: 'Threshold scheme identifier.',
    valueHelp: 'name',
  );
}

void addThresholdFlagOptions(ArgParser parser, {required bool mandatory}) {
  parser
    ..addOption(
      't',
      mandatory: mandatory,
      help: 'Threshold quorum size.',
      valueHelp: 'int',
    )
    ..addOption(
      'n',
      mandatory: mandatory,
      help: 'Total participant count.',
      valueHelp: 'int',
    );
  addSchemeOption(parser);
}

SchemeId schemeFrom(ArgResults results) {
  final name = results['scheme'] as String? ?? 'frost-ed25519-v1';
  final scheme = schemeIdsByCliName[name];
  if (scheme == null) {
    throw ArgumentError('Unknown scheme: $name');
  }
  return scheme;
}

ThresholdParams paramsFromFlags(ArgResults results) {
  final tRaw = results['t'] as String?;
  final nRaw = results['n'] as String?;
  if (tRaw == null || nRaw == null) {
    throw ArgumentError('Both --t and --n are required');
  }
  final t = int.tryParse(tRaw);
  final n = int.tryParse(nRaw);
  if (t == null) throw ArgumentError('--t must be an integer');
  if (n == null) throw ArgumentError('--n must be an integer');
  return ThresholdParams.tOfN(t: t, n: n, scheme: schemeFrom(results));
}

Future<Uint8List> readBytes(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw FileSystemException('File not found', path);
  }
  return file.readAsBytes();
}

Future<Map<String, Object?>> readJsonMap(String path) async {
  final text = await File(path).readAsString();
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object in $path');
  }
  return decoded;
}

String bytesToHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

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

void printThresholdParams(ThresholdParams params) {
  console.detail('threshold', '${params.t}-of-${params.n}');
  console.detail('scheme', schemeDisplayName(params.scheme));
  console.detail('max n', '${params.scheme.maxParticipants}');
  console.detail('wire length', '${params.toBytes().length} bytes');
}

void handleCliError(Object error) {
  switch (error) {
    case ThresholdException(:final message):
      console.failure(message);
      exitCode = 65;
      return;
    case FileSystemException(:final message, :final path):
      final suffix = path == null ? '' : ' ($path)';
      console.failure('$message$suffix');
      exitCode = 66;
      return;
    case FormatException(:final message):
      console.failure('Malformed input: $message');
      exitCode = 65;
      return;
    case ArgumentError(:final message, :final name):
      console.failure(name == null ? '$message' : '$name: $message');
      exitCode = 64;
      return;
    default:
      throw error;
  }
}
