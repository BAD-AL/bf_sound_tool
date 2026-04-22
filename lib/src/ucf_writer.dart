import 'dart:typed_data';
import 'ucf_chunk.dart';

/// Serialises a UCF chunk tree to bytes.
///
/// Chunks in [bodyReplacements] (keyed by [UcfChunk.offset]) have their body
/// replaced with the provided bytes. All other leaf chunks are copied verbatim
/// from [source]. Parent chunk sizes are recalculated bottom-up automatically.
class UcfWriter {
  static Uint8List serialize(
    UcfChunk root,
    Uint8List source,
    Map<int, Uint8List> bodyReplacements, {
    Set<int> skipOffsets = const {},
  }) {
    final out = BytesBuilder(copy: false);
    _writeChunk(root, source, bodyReplacements, skipOffsets, out);
    return out.toBytes();
  }

  static void _writeChunk(
    UcfChunk chunk,
    Uint8List source,
    Map<int, Uint8List> replacements,
    Set<int> skipOffsets,
    BytesBuilder out,
  ) {
    final Uint8List body;

    if (replacements.containsKey(chunk.offset)) {
      body = replacements[chunk.offset]!;
    } else if (chunk.hasChildren) {
      final childOut = BytesBuilder(copy: false);
      for (final child in chunk.children) {
        if (skipOffsets.contains(child.offset)) continue;
        _writeChunk(child, source, replacements, skipOffsets, childOut);
      }
      body = childOut.toBytes();
    } else {
      body = Uint8List.sublistView(
        source, chunk.bodyOffset, chunk.bodyOffset + chunk.size);
    }

    final hdr = ByteData(8);
    hdr.setUint32(0, chunk.id, Endian.little);
    hdr.setUint32(4, body.length, Endian.little);
    out.add(hdr.buffer.asUint8List());
    out.add(body);
    // UCF children are 4-byte aligned.
    final pad = (4 - body.length & 3) & 3;
    if (pad > 0) out.add(Uint8List(pad));
  }
}
