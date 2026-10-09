/// Metadata-only share decode, public disposal, and SecretBuffer windowing.
///
/// The custodian gap this covers: a third-party key store that holds shares as
/// opaque sealed bytes cannot learn a share's `t`, `n`, `participantId`, `index`
/// or `ceremonyId` without `Share.fromBytes`, which fully materializes the
/// 32-byte secret scalar into a live `SecretBuffer`. `doc/TERMINAL.md` requires
/// a share to be unwrapped only in process, so reading metadata must not require
/// unwrapping — otherwise a store can only validate what it holds by first
/// exposing what it holds.
library;

import 'dart:typed_data';

import 'package:pqthreshold/pqthreshold.dart';
import 'package:test/test.dart';

/// A 3-of-5 share produced by the dealer VSS path.
Share _share({ThresholdParams? params}) {
  final resolved = params ??
      ThresholdParams.tOfN(t: 3, n: 5, scheme: SchemeId.frostEd25519V1);
  final result = VerifiableSecretSharing.split(
    params: resolved,
    ceremonyId: generateCeremonyId(),
    secret: Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
    participantIds: const ['alice', 'bob', 'carol', 'dave', 'erin'],
  );
  return result.shares.first;
}

void main() {
  group('ShareMetadata — metadata without the secret', () {
    test('reads t, n, index, participantId and ceremonyId from serialized bytes',
        () {
      final share = _share();
      final bytes = share.toBytes();

      final metadata = ShareMetadata.fromBytes(bytes);

      expect(metadata.threshold, 3);
      expect(metadata.totalParticipants, 5);
      expect(metadata.index, share.index);
      expect(metadata.participantId, share.participantId);
      expect(metadata.ceremonyId, share.ceremonyId);
      expect(metadata.scheme, SchemeId.frostEd25519V1);
      expect(metadata.formatVersion, 0x01);
    });

    test('agrees with the Share it was derived from', () {
      final share = _share();
      final metadata = ShareMetadata.fromBytes(share.toBytes());

      expect(metadata.params, share.params);
      expect(metadata.ceremonyId, share.ceremonyId);
      expect(metadata.participantId, share.participantId);
      expect(metadata.index, share.index);
    });

    test('toString does not leak any secret material', () {
      final metadata = ShareMetadata.fromBytes(_share().toBytes());
      // Participant id and index are metadata, not secrets, and are expected.
      // The scalar must never appear.
      expect(metadata.toString(), isNot(contains('secretShare')));
      expect(metadata.toString(), startsWith('ShareMetadata('));
    });

    test('equality and hashCode are consistent', () {
      final bytes = _share().toBytes();
      final a = ShareMetadata.fromBytes(bytes);
      final b = ShareMetadata.fromBytes(bytes);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('a non-share PQTH object is refused', () {
      // A public key object: right magic and version, wrong kind.
      final share = _share();
      final publicKey = VerifiableSecretSharing.split(
        params: ThresholdParams.tOfN(t: 3, n: 5, scheme: SchemeId.frostEd25519V1),
        ceremonyId: share.ceremonyId,
        secret: Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
        participantIds: const ['alice', 'bob', 'carol', 'dave', 'erin'],
      ).publicKey;

      final mutated = Uint8List.fromList(publicKey.toBytes());
      mutated[5] = mutated[5] == 0x02 ? 0x01 : 0x02; // flip the kind byte

      expect(
        () => ShareMetadata.fromBytes(mutated),
        throwsA(isA<SerializationError>()),
      );
    });

    test('truncation before the metadata completes is refused', () {
      final bytes = _share().toBytes();

      // Everything up to and including the header, then nothing.
      expect(
        () => ShareMetadata.fromBytes(Uint8List.sublistView(bytes, 0, 8)),
        throwsA(isA<SerializationError>()),
      );
      // Header plus a partial ceremony id.
      expect(
        () => ShareMetadata.fromBytes(Uint8List.sublistView(bytes, 0, 20)),
        throwsA(isA<SerializationError>()),
      );
    });

    test('the secret tail is never parsed: garbage there still decodes', () {
      // The strongest available proof that the scalar is not read. If the
      // decoder parsed or validated the secret share, garbage in that region
      // would fail. It does not, because the metadata prefix is complete
      // before the secret begins.
      final bytes = _share().toBytes();
      final data = ByteData.sublistView(bytes);
      final idLengthOffset = 8 + 16 + 16;
      final idLength = data.getUint32(idLengthOffset, Endian.big);
      final secretOffset = idLengthOffset + 4 + idLength + 2; // +2 for u16 index

      final corrupted = Uint8List.fromList(bytes);
      // Overwrite the whole secret region with non-scalar-length garbage.
      for (var i = secretOffset; i < corrupted.length; i++) {
        corrupted[i] = 0xEE;
      }

      final metadata = ShareMetadata.fromBytes(corrupted);
      expect(metadata.threshold, 3);
      expect(metadata.index, greaterThanOrEqualTo(1));

      // And the same bytes cannot be turned back into a Share.
      expect(
        () => Share.fromBytes(corrupted),
        throwsA(isA<SerializationError>()),
        reason: 'full decode still fails closed on a corrupt secret',
      );
    });

    test('a truncated secret tail still yields metadata', () {
      // The point of the feature: metadata lives in the prefix, so a reader
      // that only needs metadata must not care that the tail is incomplete.
      final bytes = _share().toBytes();

      final metadata =
          ShareMetadata.fromBytes(Uint8List.sublistView(bytes, 0, bytes.length - 8));

      expect(metadata.threshold, 3);
      expect(metadata.totalParticipants, 5);
    });

    test('a bad magic or version is refused', () {
      final bytes = _share().toBytes();

      final badMagic = Uint8List.fromList(bytes)..[0] = 0x00;
      expect(() => ShareMetadata.fromBytes(badMagic),
          throwsA(isA<SerializationError>()));

      final badVersion = Uint8List.fromList(bytes)..[4] = 0x99;
      expect(() => ShareMetadata.fromBytes(badVersion),
          throwsA(isA<SerializationError>()));
    });

    test('an out-of-range index in the metadata is refused', () {
      // Layout: header(8) || ceremonyId(16) || params(16) ||
      //         u32BE len || participantId || u16BE index.
      final bytes = _share().toBytes();
      final data = ByteData.sublistView(bytes);
      final idLengthOffset = 8 + 16 + 16;
      final idLength = data.getUint32(idLengthOffset, Endian.big);
      final indexOffset = idLengthOffset + 4 + idLength;
      expect(idLength, 'alice'.length, reason: 'fixture participant id');

      final mutated = Uint8List.fromList(bytes);
      mutated[indexOffset] = 0;
      mutated[indexOffset + 1] = 9; // 9 > n = 5

      expect(() => ShareMetadata.fromBytes(mutated),
          throwsA(isA<InvalidParams>()));
    });
  });

  group('public validators', () {
    final params = ThresholdParams.tOfN(t: 3, n: 5, scheme: SchemeId.frostEd25519V1);

    test('validateShareIndex accepts 1..n and refuses everything else', () {
      for (var i = 1; i <= 5; i++) {
        expect(() => validateShareIndex(i, params), returnsNormally);
      }
      for (final bad in <int>[0, -1, 6, 255, 65535]) {
        expect(() => validateShareIndex(bad, params),
            throwsA(isA<InvalidParams>()),
            reason: 'index $bad must be refused');
      }
    });

    test('validateParticipantId accepts and refuses per the documented bound', () {
      expect(() => validateParticipantId('alice'), returnsNormally);
      expect(() => validateParticipantId('x' * maxParticipantIdCodeUnits),
          returnsNormally);
      expect(() => validateParticipantId(''), throwsA(isA<InvalidParams>()));
      expect(
        () => validateParticipantId('x' * (maxParticipantIdCodeUnits + 1)),
        throwsA(isA<InvalidParams>()),
      );
    });
  });

  group('Share.disposeSecret is reachable', () {
    test('a share can be disposed by external code', () {
      final share = _share();
      expect(() => share.disposeSecret(), returnsNormally);
    });

    test('disposal is idempotent', () {
      final share = _share()..disposeSecret();
      expect(() => share.disposeSecret(), returnsNormally);
    });

    test('metadata survives disposal of the secret', () {
      final share = _share();
      final participantId = share.participantId;
      final index = share.index;
      share.disposeSecret();

      // Description survives; the scalar does not.
      expect(share.participantId, participantId);
      expect(share.index, index);
      expect(share.params.n, 5);
    });
  });

  group('SecretBuffer windowing avoids untracked copies', () {
    test('use hands out the managed buffer, not a copy', () {
      // Pass the buffer directly: SecretBuffer takes ownership and zeroes the
      // argument, which is the zeroize contract we are asserting.
      final source = Uint8List.fromList(List<int>.generate(32, (i) => i + 7));
      final buffer = SecretBuffer(source);
      addTearDown(buffer.dispose);

      late Uint8List seen;
      buffer.use((b) {
        seen = b;
      });

      expect(source.every((b) => b == 0), isTrue,
          reason: 'the buffer handed to SecretBuffer must be zeroed');
      expect(seen.every((b) => b != 0), isTrue,
          reason: 'use must expose live material, not zeros');
      expect(identical(seen, source), isFalse,
          reason: 'SecretBytes always copies, so use must not alias the '
              'caller\'s buffer');
    });

    test('the managed buffer is wiped on dispose, and use sees it', () {
      final buffer = SecretBuffer(Uint8List.fromList(List<int>.filled(32, 0xAB)));
      late Uint8List backing;
      buffer.use((b) => backing = b);
      expect(backing.every((b) => b == 0xAB), isTrue);

      buffer.dispose();

      expect(backing.every((b) => b == 0), isTrue,
          reason: 'dispose must wipe the exact buffer use() exposed');
    });

    test('mutate writes through to the managed buffer', () {
      final buffer = SecretBuffer(Uint8List.fromList(List<int>.filled(16, 1)));
      addTearDown(buffer.dispose);

      buffer.mutate((b) => b[0] = 9);

      expect(buffer.use((b) => b[0]), 9);
    });

    test('bytes still returns a caller-owned snapshot', () {
      final buffer = SecretBuffer(Uint8List.fromList(List<int>.filled(8, 5)));
      addTearDown(buffer.dispose);

      final snapshot = buffer.bytes;
      snapshot[0] = 0;

      expect(buffer.use((b) => b[0]), 5,
          reason: 'the snapshot must not alias the managed buffer');
    });

    test('use and mutate throw after dispose', () {
      final buffer = SecretBuffer(Uint8List.fromList(List<int>.filled(8, 5)))..dispose();

      expect(() => buffer.use((b) => b), throwsA(isA<StateError>()));
      expect(() => buffer.mutate((b) => b), throwsA(isA<StateError>()));
      expect(() => buffer.bytes, throwsA(isA<StateError>()));
    });
  });
}