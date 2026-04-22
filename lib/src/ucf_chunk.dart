import 'dart:typed_data';

class UcfChunk {
  final int id;
  final int size;
  final int offset;         // file offset of the 4-byte ID field
  final List<UcfChunk> children;

  const UcfChunk({
    required this.id,
    required this.size,
    required this.offset,
    this.children = const [],
  });

  int get bodyOffset => offset + 8;
  bool get hasChildren => children.isNotEmpty;

  String get idLabel {
    final bytes = [id & 0xff, (id >> 8) & 0xff, (id >> 16) & 0xff, (id >> 24) & 0xff];
    if (bytes.every((b) => b >= 0x20 && b < 0x7f)) {
      return "'${String.fromCharCodes(bytes)}'";
    }
    return '0x${id.toRadixString(16).padLeft(8, '0')}';
  }

  /// Recursively walk this chunk and its descendants, yielding every node.
  Iterable<UcfChunk> allChunks() sync* {
    yield this;
    for (final child in children) {
      yield* child.allChunks();
    }
  }

  @override
  String toString() =>
      'UcfChunk(${idLabel} @ 0x${offset.toRadixString(16)}, '
      'size=0x${size.toRadixString(16)}, children=${children.length})';
}
