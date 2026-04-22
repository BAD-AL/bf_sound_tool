import 'dart:typed_data';

/// Decodes PS2 SPU ADPCM (VAG) to signed 16-bit PCM.
///
/// Each VAG block is 16 bytes:
///   byte 0: (filter << 4) | shift
///   byte 1: flags  (0x00=normal, 0x01=end, 0x02=loop-start, 0x03=loop-end, 0x04=play-once-end)
///   bytes 2..15: 14 bytes of packed 4-bit ADPCM nibbles → 28 samples
///
/// Stereo streams interleave left and right channels in [substreamInterleave]-byte
/// chunks: [L chunk 0][R chunk 0][L chunk 1][R chunk 1]...
class VagDecoder {
  static const int blockSize = 16;
  static const int samplesPerBlock = 28;

  // PS2 SPU prediction coefficients (f0, f1) for filter indices 0-4.
  static const List<double> _f0 = [0.0, 0.9375, 1.796875, 1.53125, 1.90625];
  static const List<double> _f1 = [0.0, 0.0, -0.8125, -0.859375, -0.9375];

  /// Decode [vagData] to interleaved signed PCM16 bytes.
  ///
  /// [channels]: 1 = mono, 2 = stereo.
  /// [substreamInterleave]: interleave block size in bytes for stereo (e.g. 16384).
  ///   Ignored for mono.
  static Uint8List decode(
    Uint8List vagData,
    int channels,
    int substreamInterleave,
  ) {
    if (channels == 1) return _decodeMono(vagData);
    return _decodeStereo(vagData, substreamInterleave);
  }

  // ── Mono ─────────────────────────────────────────────────────────────────

  static Uint8List _decodeMono(Uint8List data) {
    final totalBlocks = data.length ~/ blockSize;
    final out = Int16List(totalBlocks * samplesPerBlock);
    int s1 = 0, s2 = 0;
    int outOff = 0;
    for (int b = 0; b < totalBlocks; b++) {
      _decodeBlock(data, b * blockSize, out, outOff, s1, s2, (ns1, ns2) {
        s1 = ns1;
        s2 = ns2;
      });
      outOff += samplesPerBlock;
    }
    return out.buffer.asUint8List();
  }

  // ── Stereo ────────────────────────────────────────────────────────────────
  //
  // Left and right channels are interleaved in [interleaveBytes]-byte chunks:
  //   [interleaveBytes of L][interleaveBytes of R][interleaveBytes of L]...
  //
  // Each chunk contains (interleaveBytes / blockSize) VAG blocks.
  // Output is interleaved stereo PCM16: [L0 R0 L1 R1 ...].

  static Uint8List _decodeStereo(Uint8List data, int interleaveBytes) {
    final blocksPerChunk = interleaveBytes ~/ blockSize;
    final totalBlocks = data.length ~/ blockSize;

    // Separate the two channels into their own block arrays first.
    final chL = <int>[];
    final chR = <int>[];
    int sL1 = 0, sL2 = 0, sR1 = 0, sR2 = 0;

    int blockIdx = 0;
    while (blockIdx < totalBlocks) {
      // Left channel chunk
      final lCount = _blocksInChunk(blockIdx, blocksPerChunk, totalBlocks);
      for (int b = 0; b < lCount; b++) {
        final tmp = Int16List(samplesPerBlock);
        _decodeBlock(data, (blockIdx + b) * blockSize, tmp, 0, sL1, sL2,
            (ns1, ns2) { sL1 = ns1; sL2 = ns2; });
        chL.addAll(tmp);
      }
      blockIdx += lCount;
      if (blockIdx >= totalBlocks) break;

      // Right channel chunk
      final rCount = _blocksInChunk(blockIdx, blocksPerChunk, totalBlocks);
      for (int b = 0; b < rCount; b++) {
        final tmp = Int16List(samplesPerBlock);
        _decodeBlock(data, (blockIdx + b) * blockSize, tmp, 0, sR1, sR2,
            (ns1, ns2) { sR1 = ns1; sR2 = ns2; });
        chR.addAll(tmp);
      }
      blockIdx += rCount;
    }

    // Interleave L and R into stereo PCM16
    final len = chL.length < chR.length ? chL.length : chR.length;
    final stereo = Int16List(len * 2);
    for (int i = 0; i < len; i++) {
      stereo[i * 2]     = chL[i];
      stereo[i * 2 + 1] = chR[i];
    }
    return stereo.buffer.asUint8List();
  }

  static int _blocksInChunk(int start, int blocksPerChunk, int total) {
    final remaining = total - start;
    return remaining < blocksPerChunk ? remaining : blocksPerChunk;
  }

  // ── Block decoder ─────────────────────────────────────────────────────────

  static void _decodeBlock(
    Uint8List data,
    int offset,
    Int16List out,
    int outOffset,
    int s1,
    int s2,
    void Function(int s1, int s2) saveState,
  ) {
    final header = data[offset];
    final shift  = 12 - (header & 0x0F);
    final filter = (header >> 4) & 0x0F;
    // byte[1] is flags — we decode all blocks regardless (file size is authoritative)

    final f0 = filter < _f0.length ? _f0[filter] : 0.0;
    final f1 = filter < _f1.length ? _f1[filter] : 0.0;

    int idx = outOffset;
    for (int i = 0; i < 14; i++) {
      final byte = data[offset + 2 + i];
      // Low nibble first, then high nibble
      for (int nibbleIdx = 0; nibbleIdx < 2; nibbleIdx++) {
        final raw = nibbleIdx == 0 ? (byte & 0x0F) : ((byte >> 4) & 0x0F);
        // Sign-extend 4-bit value
        final signed = raw > 7 ? raw - 16 : raw;
        final sample = ((signed << shift) + f0 * s1 + f1 * s2).round();
        final clamped = sample.clamp(-32768, 32767);
        out[idx++] = clamped;
        s2 = s1;
        s1 = clamped;
      }
    }

    saveState(s1, s2);
  }
}
