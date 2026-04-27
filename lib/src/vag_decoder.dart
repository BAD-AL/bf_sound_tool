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

  // PS2 SPU prediction coefficients scaled by 2048 for integer math.
  static const List<int> _k0 = [0, 1920, 3680, 3136, 3904];
  static const List<int> _k1 = [0, 0, -1664, -1760, -1920];

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
    if (interleaveBytes <= 0) {
      // Fallback: if interleave is invalid, treat as mono or return empty.
      // For robustness, we'll return an empty list or decode as mono.
      // Given this is a safety check, mono fallback is least likely to crash.
      return _decodeMono(data);
    }
    final totalBlocks = data.length ~/ blockSize;
    final maxSamplesPerChannel = totalBlocks * samplesPerBlock;

    final chL = Int16List(maxSamplesPerChannel);
    final chR = Int16List(maxSamplesPerChannel);
    int sL1 = 0, sL2 = 0, sR1 = 0, sR2 = 0;
    int lOff = 0, rOff = 0;

    final blocksPerChunk = interleaveBytes ~/ blockSize;
    int blockIdx = 0;
    while (blockIdx < totalBlocks) {
      // Left channel chunk
      final lCount = _blocksInChunk(blockIdx, blocksPerChunk, totalBlocks);
      for (int b = 0; b < lCount; b++) {
        _decodeBlock(data, (blockIdx + b) * blockSize, chL, lOff, sL1, sL2,
            (ns1, ns2) { sL1 = ns1; sL2 = ns2; });
        lOff += samplesPerBlock;
      }
      blockIdx += lCount;
      if (blockIdx >= totalBlocks) break;

      // Right channel chunk
      final rCount = _blocksInChunk(blockIdx, blocksPerChunk, totalBlocks);
      for (int b = 0; b < rCount; b++) {
        _decodeBlock(data, (blockIdx + b) * blockSize, chR, rOff, sR1, sR2,
            (ns1, ns2) { sR1 = ns1; sR2 = ns2; });
        rOff += samplesPerBlock;
      }
      blockIdx += rCount;
    }

    // Interleave L and R into stereo PCM16
    final len = lOff < rOff ? lOff : rOff;
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

    final k0 = filter < _k0.length ? _k0[filter] : 0;
    final k1 = filter < _k1.length ? _k1[filter] : 0;

    int idx = outOffset;
    for (int i = 0; i < 14; i++) {
      final byte = data[offset + 2 + i];
      for (int nibbleIdx = 0; nibbleIdx < 2; nibbleIdx++) {
        final raw = nibbleIdx == 0 ? (byte & 0x0F) : ((byte >> 4) & 0x0F);
        final signed = raw > 7 ? raw - 16 : raw;
        
        // Fixed-point integer math (11-bit scale)
        int sample = (signed << shift) << 11;
        sample += (s1 * k0) + (s2 * k1);
        sample = (sample + 1024) >> 11;

        final clamped = sample.clamp(-32768, 32767);
        out[idx++] = clamped;
        s2 = s1;
        s1 = clamped;
      }
    }

    saveState(s1, s2);
  }
}
