/// PQTH format constants (`doc/SERIALIZATION.md` §3.1).
library;

/// ASCII magic `PQTH`.
const List<int> pqthMagicBytes = [0x50, 0x51, 0x54, 0x48];

/// Current durable object format version.
const int pqthFormatVersion = 0x01;

/// Length of the fixed PQTH header (magic + ver + kind + scheme).
const int pqthHeaderLength = 8;

/// Expected length of a serialized [ThresholdParams] object.
const int thresholdParamsEncodedLength = pqthHeaderLength + 2 + 2 + 4;
