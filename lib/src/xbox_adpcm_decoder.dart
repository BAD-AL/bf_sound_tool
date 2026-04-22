import 'dart:typed_data';

/// Decodes Xbox ADPCM (WAVE_FORMAT_XBOX_ADPCM, 0x0069) blocks to PCM16.
///
/// Block layout — mono (blockAlign = 36):
///   bytes 0-1 : initial predictor (int16 LE) → output as sample[0]
///   byte  2   : initial step index (0-88)
///   byte  3   : reserved
///   bytes 4-35: 32 bytes × 2 nibbles/byte = 64 nibbles → samples[1..64]
///   → 65 samples per block
///
/// Stereo (blockAlign = 72):
///   bytes 0-3 : left channel header (same layout as mono header)
///   bytes 4-7 : right channel header
///   bytes 8-71: 64 bytes of interleaved nibbles — 4 bytes L, 4 bytes R, …
///   → 65 samples per channel per block, output as interleaved L/R PCM16
class XboxAdpcmDecoder {
  static const List<int> _stepTable = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
    157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658,
    724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024,
    3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
  ];

  // Index delta for each nibble magnitude (bits 0-2).
  static const List<int> _indexTable = [-1, -1, -1, -1, 2, 4, 6, 8];

  /// Decodes raw Xbox ADPCM [blocks] to signed PCM16 bytes.
  /// [channels]: 1 = mono (blockAlign 36), 2 = stereo (blockAlign 72).
  static Uint8List decode(Uint8List blocks, int channels) =>
      channels == 2 ? _decodeStereo(blocks) : _decodeMono(blocks);

  // ── Mono ──────────────────────────────────────────────────────────────────

  static Uint8List _decodeMono(Uint8List blocks) {
    const blockAlign = 36;
    const samplesPerBlock = 65; // 1 header predictor + 64 nibbles
    final blockCount = blocks.length ~/ blockAlign;
    final out = Int16List(blockCount * samplesPerBlock);
    int outOff = 0;

    for (int b = 0; b < blockCount; b++) {
      final o = b * blockAlign;
      int pred = _int16(blocks, o);
      int idx  = blocks[o + 2].clamp(0, 88);
      out[outOff++] = pred;

      for (int i = 0; i < 32; i++) {
        final byte = blocks[o + 4 + i];
        _decodeNibble(byte & 0x0F,        pred, idx, (p, x) { pred = p; idx = x; out[outOff++] = p; });
        _decodeNibble((byte >> 4) & 0x0F, pred, idx, (p, x) { pred = p; idx = x; out[outOff++] = p; });
      }
    }

    return out.buffer.asUint8List();
  }

  // ── Stereo ────────────────────────────────────────────────────────────────

  static Uint8List _decodeStereo(Uint8List blocks) {
    const blockAlign = 72;
    const samplesPerBlock = 65;
    final blockCount = blocks.length ~/ blockAlign;
    // Decode L and R into separate arrays, then interleave.
    final outL = Int16List(blockCount * samplesPerBlock);
    final outR = Int16List(blockCount * samplesPerBlock);

    for (int b = 0; b < blockCount; b++) {
      final o = b * blockAlign;
      int predL = _int16(blocks, o);
      int idxL  = blocks[o + 2].clamp(0, 88);
      int predR = _int16(blocks, o + 4);
      int idxR  = blocks[o + 6].clamp(0, 88);

      int lOff = b * samplesPerBlock, rOff = b * samplesPerBlock;
      outL[lOff++] = predL;
      outR[rOff++] = predR;

      // Nibble data: 16 chunks of 4 bytes each, alternating L / R.
      for (int chunk = 0; chunk < 16; chunk++) {
        final isLeft = chunk.isEven;
        final base = o + 8 + chunk * 4;
        for (int i = 0; i < 4; i++) {
          final byte = blocks[base + i];
          if (isLeft) {
            _decodeNibble(byte & 0x0F,        predL, idxL, (p, x) { predL = p; idxL = x; outL[lOff++] = p; });
            _decodeNibble((byte >> 4) & 0x0F, predL, idxL, (p, x) { predL = p; idxL = x; outL[lOff++] = p; });
          } else {
            _decodeNibble(byte & 0x0F,        predR, idxR, (p, x) { predR = p; idxR = x; outR[rOff++] = p; });
            _decodeNibble((byte >> 4) & 0x0F, predR, idxR, (p, x) { predR = p; idxR = x; outR[rOff++] = p; });
          }
        }
      }
    }

    final total = blockCount * samplesPerBlock;
    final out = Int16List(total * 2);
    for (int i = 0; i < total; i++) {
      out[i * 2]     = outL[i];
      out[i * 2 + 1] = outR[i];
    }
    return out.buffer.asUint8List();
  }

  // ── IMA ADPCM core ────────────────────────────────────────────────────────

  static void _decodeNibble(
    int nibble,
    int predictor,
    int stepIdx,
    void Function(int predictor, int stepIdx) save,
  ) {
    final step      = _stepTable[stepIdx];
    final magnitude = nibble & 0x07;
    int diff = step >> 3;
    if (magnitude & 0x04 != 0) diff += step;
    if (magnitude & 0x02 != 0) diff += step >> 1;
    if (magnitude & 0x01 != 0) diff += step >> 2;
    final newPred = (nibble & 0x08 != 0 ? predictor - diff : predictor + diff)
        .clamp(-32768, 32767);
    save(newPred, (stepIdx + _indexTable[magnitude]).clamp(0, 88));
  }

  static int _int16(Uint8List b, int o) {
    final v = b[o] | (b[o + 1] << 8);
    return v > 32767 ? v - 65536 : v;
  }
}
