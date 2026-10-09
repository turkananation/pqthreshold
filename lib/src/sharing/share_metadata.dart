/// Metadata-only decode for a serialized [Share] (`doc/SERIALIZATION.md` §4.2).
///
/// A third-party custodian that stores shares as opaque sealed bytes cannot
/// currently learn a share's `t`, `n`, `participantId`, `index` or `ceremonyId`
/// without calling `Share.fromBytes` — which fully materializes the 32-byte
/// secret scalar into a live `SecretBuffer`. That inverts the custody model:
/// `doc/TERMINAL.md` requires that a share be unwrapped only in process, so
/// reading metadata must not require unwrapping in the first place.
///
/// [ShareMetadata] parses only the leading metadata fields and never touches
/// the secret share or the verification blob.
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';

import '../errors/threshold_exception.dart';
import '../params/params_validation.dart';
import '../params/scheme_id.dart';
import '../params/threshold_params.dart';
import '../serialization/binary_codec.dart';
import '../serialization/pqth_format.dart';
import '../serialization/pqth_header.dart';
import '../serialization/pqth_kind.dart';
import '../util/ceremony_id.dart';

/// The non-secret description of a serialized share.
///
/// Obtain one with [ShareMetadata.fromBytes].
final class ShareMetadata {
  /// Creates share metadata. Public so a custodian can describe a share it
  /// holds; not intended for constructing one that came from elsewhere.
  const ShareMetadata({
    required this.params,
    required this.ceremonyId,
    required this.participantId,
    required this.index,
    required this.formatVersion,
  });

  /// Threshold parameters (`t`, `n`, scheme) bound to the share.
  final ThresholdParams params;

  /// Ceremony identifier (16 bytes).
  final Uint8List ceremonyId;

  /// Application-assigned participant label.
  final String participantId;

  /// 1-based Shamir evaluation index, in `1..n`.
  final int index;

  /// PQTH format version byte the share was serialized with.
  final int formatVersion;

  /// Threshold `t`.
  int get threshold => params.t;

  /// Total participants `n`.
  int get totalParticipants => params.n;

  /// Threshold scheme.
  SchemeId get scheme => params.scheme;

  /// Parses the metadata prefix of serialized share [bytes].
  ///
  /// Reads only `header || ceremonyId || params || participantId || index` and
  /// stops there. The secret share and the verification blob are never
  /// allocated, copied, or held.
  ///
  /// Throws [SerializationError] when [bytes] is not a well-formed PQTH share
  /// or is truncated before the metadata is complete, and [InvalidParams] when
  /// the decoded `index` is outside `1..n`.
  ///
  /// ## What this does not do
  ///
  /// Reading metadata is **not** authentication. It reports what the bytes
  /// claim to be; it does not prove the share is authentic, intact, or
  /// internally consistent. A caller that needs those properties must unwrap
  /// the share and use `VerifiableSecretSharing.verifyShare`. This type is for
  /// describing and indexing shares, never for trusting them.
  factory ShareMetadata.fromBytes(Uint8List bytes) {
    final (header, payload) = _split(bytes);
    if (header.kind != PqthObjectKind.share) {
      throw SerializationError('Expected Share kind 0x02');
    }
    final reader = BinaryReader(payload);
    final ceremonyId = reader.readBytes(ceremonyIdLength);
    final params = ThresholdParams.fromBytes(
      reader.readBytes(thresholdParamsEncodedLength),
    );
    if (params.scheme != header.scheme) {
      throw SerializationError('Share scheme mismatch with header');
    }
    final participantId =
        String.fromCharCodes(_readLengthPrefixed(reader));
    final index = reader.readUint16Be();

    // Stop here. The secret share and verificationData that follow are never
    // read, so the secret scalar never exists in this process.
    validateCeremonyId(ceremonyId);
    validateShareIndex(index, params);
    validateParticipantId(participantId);

    return ShareMetadata(
      params: params,
      ceremonyId: Uint8List.fromList(ceremonyId),
      participantId: participantId,
      index: index,
      formatVersion: header.version,
    );
  }

  static (PqthHeader header, Uint8List payload) _split(Uint8List bytes) {
    final header = PqthHeader.decode(bytes);
    if (bytes.length < pqthHeaderLength) {
      throw SerializationError('Truncated PQTH object');
    }
    return (header, Uint8List.sublistView(bytes, pqthHeaderLength));
  }

  static Uint8List _readLengthPrefixed(BinaryReader reader) =>
      reader.readBytes(reader.readUint32Be());

  @override
  String toString() => 'ShareMetadata(scheme: ${params.scheme.name}, '
      't: $threshold, n: $totalParticipants, index: $index, '
      'participantId: $participantId, version: $formatVersion)';

  @override
  bool operator ==(Object other) =>
      other is ShareMetadata &&
      other.params == params &&
      PqBytes.constantTimeEquals(other.ceremonyId, ceremonyId) &&
      other.participantId == participantId &&
      other.index == index &&
      other.formatVersion == formatVersion;

  @override
  int get hashCode =>
      Object.hash(params, Object.hashAll(ceremonyId), participantId, index, formatVersion);
}