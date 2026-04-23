import 'dart:typed_data';
import 'byte_reader.dart';
import 'ucf_chunk.dart';

class UcfParser {
  static const int idUcfb = 0x62666375; // 'ucfb' — root
  static const int idInfo = 0x0fb40705; // 'info' — bank metadata
  static const int idData = 0xd872e2a5; // 'data' — bank audio

  /// Parse a UCF file from raw bytes. Returns the root `ucfb` chunk.
  static UcfChunk parse(Uint8List bytes) {
    return _parseAt(ByteReader(bytes), 0, bytes.length);
  }

  static UcfChunk _parseAt(ByteReader r, int offset, int fileSize) {
    r.seek(offset);
    final id = r.readUint32();
    final size = r.readUint32();

    final bodyOffset = offset + 8;
    final children = _tryParseChildren(r, bodyOffset, size, fileSize);
    return UcfChunk(id: id, size: size, offset: offset, children: children);
  }

  /// Try to interpret the body at [bodyOffset] of [bodySize] bytes as a
  /// sequence of child chunks. Returns the child list on success, or an empty
  /// list if the body is a leaf (audio data, tagged pairs, etc.).
  ///
  /// Heuristic: every child must have a non-zero ID and its aligned total size
  /// must fit within the body. Children must consume the body exactly.
  static List<UcfChunk> _tryParseChildren(
    ByteReader r,
    int bodyOffset,
    int bodySize,
    int fileSize,
  ) {
    if (bodySize < 8) return const [];
    if (bodyOffset + bodySize > fileSize) return const [];

    // Quick rejection: a zero first ID means audio silence or empty body.
    final firstId = r.peekUint32(bodyOffset);
    if (firstId == 0) return const [];

    final children = <UcfChunk>[];
    int pos = bodyOffset;
    final end = bodyOffset + bodySize;

    while (pos + 8 <= end) {
      final childId = r.peekUint32(pos);
      final childSize = r.peekUint32(pos + 4);

      if (childId == 0) return const []; // invalid child — treat whole body as leaf

      final aligned = ((childSize + 3) ~/ 4) * 4;
      final childTotal = 8 + aligned;

      if (pos + childTotal > end) return const []; // child overflows body

      children.add(_parseAt(r, pos, fileSize));
      pos += childTotal;
    }

    if (pos != end) return const []; // body not consumed exactly

    return children;
  }
}
