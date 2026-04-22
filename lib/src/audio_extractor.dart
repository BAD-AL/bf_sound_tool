import 'dart:typed_data';
import 'bank_parser.dart';
import 'byte_reader.dart';

class AudioExtractor {
  /// Extract raw audio bytes for [entry] from [fileBytes].
  ///
  /// Returns [entry.audioReadSize] bytes starting at [entry.audioOffset].
  /// For stream banks this includes any block-alignment padding; for sample
  /// banks the raw size and read size are equal (no padding).
  static Uint8List extract(Uint8List fileBytes, SoundEntry entry) {
    return Uint8List.sublistView(
      fileBytes,
      entry.audioOffset,
      entry.audioOffset + entry.audioReadSize,
    );
  }

  /// Peek the uint32 LE at the start of the entry's audio data.
  /// Useful for verifying audio magic bytes in tests.
  static int peekUint32(Uint8List fileBytes, SoundEntry entry) {
    final r = ByteReader(fileBytes);
    return r.peekUint32(entry.audioOffset);
  }
}
