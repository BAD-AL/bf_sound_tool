import 'dart:typed_data';

/// Encodes mono or stereo PCM16 to raw Xbox ADPCM blocks (WAVE_FORMAT_XBOX_ADPCM, 0x0069).
///
/// Mono block layout (36 bytes):
///   bytes 0-1 : initial predictor (int16 LE) — first input sample
///   byte  2   : initial step index (carried forward from previous block)
///   byte  3   : reserved (0)
///   bytes 4-35: 32 bytes = 64 nibbles → samples[1..64]
///   → 65 samples consumed per block
///
/// Stereo block layout (72 bytes):
///   bytes 0-3 : left channel header  (int16 predictor + uint8 stepIdx + uint8 reserved)
///   bytes 4-7 : right channel header
///   bytes 8-71: 64 bytes — 16 chunks of 4 bytes alternating L / R
///               even chunks = left  (8 chunks × 8 nibbles = 64 L samples)
///               odd  chunks = right (8 chunks × 8 nibbles = 64 R samples)
///   → 65 samples per channel per block
///
/// Step index is carried across block boundaries for best quality at seams.
class XboxAdpcmEncoder {
  static const List<int> _stepTable = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
    157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658,
    724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024,
    3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
  ];

  static const List<int> _indexTable = [-1, -1, -1, -1, 2, 4, 6, 8];

  /// Encodes mono [samples] to raw Xbox ADPCM blocks (no WAV header).
  static Uint8List encode(Int16List samples) {
    if (samples.isEmpty) return Uint8List(0);
    final blockCount = (samples.length + 64) ~/ 65;
    final out = Uint8List(blockCount * 36);
    int stepIdx = 0;

    for (int b = 0; b < blockCount; b++) {
      final start = b * 65;
      final o     = b * 36;

      final pred0 = start < samples.length ? samples[start] : 0;
      _writeInt16(out, o, pred0);
      out[o + 2] = stepIdx;
      out[o + 3] = 0;

      int pred = pred0;
      int idx  = stepIdx;

      for (int i = 0; i < 32; i++) {
        final si1 = start + 1 + i * 2;
        final si2 = start + 2 + i * 2;
        final s1  = si1 < samples.length ? samples[si1] : pred;
        final s2  = si2 < samples.length ? samples[si2] : pred;

        int nibLo, nibHi;
        (nibLo, pred, idx) = _encodeNibble(s1, pred, idx);
        (nibHi, pred, idx) = _encodeNibble(s2, pred, idx);
        out[o + 4 + i] = nibLo | (nibHi << 4);
      }
      stepIdx = idx;
    }
    return out;
  }

  /// Encodes stereo L/R PCM16 to raw Xbox ADPCM stereo blocks (no WAV header).
  ///
  /// If [left] and [right] differ in length the shorter channel is padded with
  /// the last valid sample at its boundary.
  static Uint8List encodeStereo(Int16List left, Int16List right) {
    final frameCount = left.length > right.length ? left.length : right.length;
    if (frameCount == 0) return Uint8List(0);
    final blockCount = (frameCount + 64) ~/ 65;
    final out = Uint8List(blockCount * 72);
    int stepIdxL = 0, stepIdxR = 0;

    for (int b = 0; b < blockCount; b++) {
      final start = b * 65;
      final o     = b * 72;

      final pred0L = start < left.length  ? left[start]  : 0;
      final pred0R = start < right.length ? right[start] : 0;

      _writeInt16(out, o,     pred0L);
      out[o + 2] = stepIdxL;
      out[o + 3] = 0;
      _writeInt16(out, o + 4, pred0R);
      out[o + 6] = stepIdxR;
      out[o + 7] = 0;

      int predL = pred0L, idxL = stepIdxL;
      int predR = pred0R, idxR = stepIdxR;

      // 16 alternating chunks: 0,2,4,...=L  1,3,5,...=R
      for (int chunk = 0; chunk < 16; chunk++) {
        final isLeft   = chunk.isEven;
        final base     = o + 8 + chunk * 4;
        final groupIdx = chunk >> 1; // 0..7

        for (int i = 0; i < 4; i++) {
          // Within each channel, samples[1..64] are split into 8 groups of 8.
          // group g, byte i → sample pair at offset 1 + g*8 + i*2.
          final sOff = 1 + groupIdx * 8 + i * 2;
          if (isLeft) {
            final si1 = start + sOff;
            final si2 = si1 + 1;
            final s1  = si1 < left.length ? left[si1] : predL;
            final s2  = si2 < left.length ? left[si2] : predL;
            int n1, n2;
            (n1, predL, idxL) = _encodeNibble(s1, predL, idxL);
            (n2, predL, idxL) = _encodeNibble(s2, predL, idxL);
            out[base + i] = n1 | (n2 << 4);
          } else {
            final si1 = start + sOff;
            final si2 = si1 + 1;
            final s1  = si1 < right.length ? right[si1] : predR;
            final s2  = si2 < right.length ? right[si2] : predR;
            int n1, n2;
            (n1, predR, idxR) = _encodeNibble(s1, predR, idxR);
            (n2, predR, idxR) = _encodeNibble(s2, predR, idxR);
            out[base + i] = n1 | (n2 << 4);
          }
        }
      }
      stepIdxL = idxL;
      stepIdxR = idxR;
    }
    return out;
  }

  // ── IMA ADPCM nibble encoder ───────────────────────────────────────────────

  static (int nibble, int pred, int idx) _encodeNibble(
      int sample, int predictor, int stepIdx) {
    final step = _stepTable[stepIdx];
    int diff   = sample - predictor;
    int nibble = diff < 0 ? 0x08 : 0x00;
    if (diff < 0) diff = -diff;

    int code = 0;
    if (diff >= step)        { code |= 4; diff -= step; }
    if (diff >= (step >> 1)) { code |= 2; diff -= (step >> 1); }
    if (diff >= (step >> 2))   code |= 1;
    nibble |= code;

    // Reconstruct predictor using the same formula as XboxAdpcmDecoder
    // so encoder and decoder stay in sync.
    final magnitude = nibble & 0x07;
    int d = step >> 3;
    if (magnitude & 4 != 0) d += step;
    if (magnitude & 2 != 0) d += step >> 1;
    if (magnitude & 1 != 0) d += step >> 2;
    final newPred = (nibble & 8 != 0 ? predictor - d : predictor + d)
        .clamp(-32768, 32767);
    final newIdx  = (stepIdx + _indexTable[magnitude]).clamp(0, 88);

    return (nibble, newPred, newIdx);
  }

  static void _writeInt16(Uint8List b, int o, int v) {
    final u = v < 0 ? v + 65536 : v;
    b[o]     = u & 0xFF;
    b[o + 1] = (u >> 8) & 0xFF;
  }
}
