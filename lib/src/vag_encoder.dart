import 'dart:typed_data';

/// Encodes mono signed-16 PCM to PS2/PSP SPU ADPCM (raw VAG blocks, no header).
///
/// Block layout (16 bytes each):
///   byte 0: (filter << 4) | (12 - shift)   — header byte matching VagDecoder
///   byte 1: flags  (0x00=normal, 0x01=end on last block)
///   bytes 2..15: 14 bytes = 28 nibbles (low nibble first per byte)
///
/// Encoder exhaustively tests all 5 filter coefficients × 13 shift values and
/// picks the combination with minimum mean-squared reconstruction error per block.
class VagEncoder {
  // PS2 SPU prediction coefficients scaled by 2048 for integer math.
  static const List<int> _k0 = [0, 1920, 3680, 3136, 3904];
  static const List<int> _k1 = [0, 0, -1664, -1760, -1920];

  /// Encodes [samples] (mono Int16) to raw VAG ADPCM blocks.
  static Uint8List encode(Int16List samples) {
    if (samples.isEmpty) return Uint8List(0);
    final blockCount = (samples.length + 27) ~/ 28;
    final out = Uint8List(blockCount * 16);
    int prev1 = 0, prev2 = 0;

    for (int b = 0; b < blockCount; b++) {
      final start = b * 28;
      final count = (start + 28 > samples.length) ? samples.length - start : 28;

      // Zero-pad last block to 28 samples.
      final block = Int32List(28);
      for (int i = 0; i < count; i++) { block[i] = samples[start + i]; }

      // Exhaustive search: find best (filter, shift) by minimum squared error.
      int bestFilter = 0, bestShift = 0;
      double bestErr = double.maxFinite;

      for (int fi = 0; fi < 5; fi++) {
        final k0 = _k0[fi];
        final k1 = _k1[fi];
        for (int sh = 0; sh <= 12; sh++) {
          double err = 0;
          int p1 = prev1, p2 = prev2;
          for (int i = 0; i < 28; i++) {
            // Replicate VagDecoder logic for prediction
            int predicted = (p1 * k0 + p2 * k1 + 1024) >> 11;
            final scale = (1 << sh);
            final nibble = ((block[i] - predicted) / scale).round().clamp(-8, 7);
            final recon = (predicted + nibble * scale).clamp(-32768, 32767);
            final e = (block[i] - recon).toDouble();
            err += e * e;
            p2 = p1;
            p1 = recon;
          }
          if (err < bestErr) {
            bestErr = err;
            bestFilter = fi;
            bestShift = sh;
          }
        }
      }

      // Write header: VagDecoder reads shift as (12 - (byte0 & 0x0F)).
      final blockOffset = b * 16;
      out[blockOffset]     = (bestFilter << 4) | (12 - bestShift);
      out[blockOffset + 1] = (b == blockCount - 1) ? 0x01 : 0x00;

      // Encode nibbles with chosen params, updating predictor state.
      int p1 = prev1, p2 = prev2;
      final k0 = _k0[bestFilter];
      final k1 = _k1[bestFilter];
      for (int i = 0; i < 28; i++) {
        int predicted = (p1 * k0 + p2 * k1 + 1024) >> 11;
        final scale     = (1 << bestShift);
        final nibble    = ((block[i] - predicted) / scale).round().clamp(-8, 7);
        final recon     = (predicted + nibble * scale).clamp(-32768, 32767);

        final byteIdx = blockOffset + 2 + i ~/ 2;
        if (i.isEven) {
          out[byteIdx] = nibble & 0x0F;
        } else {
          out[byteIdx] |= (nibble & 0x0F) << 4;
        }
        p2 = p1;
        p1 = recon;
      }
      prev1 = p1;
      prev2 = p2;
    }

    return out;
  }

  /// Encodes stereo PCM16 to the PS2 stereo stream layout.
  ///
  /// Each channel is independently encoded as mono VAG ADPCM, then sliced
  /// into [substreamInterleave]-byte chunks and interleaved:
  ///   [chunk0_L][chunk0_R][chunk1_L][chunk1_R]...
  ///
  /// This matches the dual-substream layout that VagDecoder reads when
  /// channels == 2.
  static Uint8List encodeStereoPs2(
      Int16List left, Int16List right, int substreamInterleave) {
    final vagL = encode(left);
    final vagR = encode(right);
    return _interleave(vagL, vagR, substreamInterleave);
  }

  // ── Interleave helpers ─────────────────────────────────────────────────────

  static Uint8List _interleave(Uint8List a, Uint8List b, int chunkSize) {
    final maxLen = a.length > b.length ? a.length : b.length;
    final n = (maxLen + chunkSize - 1) ~/ chunkSize;
    final out = BytesBuilder(copy: false);
    for (int i = 0; i < n; i++) {
      _chunk(out, a, i, chunkSize);
      _chunk(out, b, i, chunkSize);
    }
    return out.toBytes();
  }

  static void _chunk(BytesBuilder out, Uint8List data, int i, int chunkSize) {
    final start = i * chunkSize;
    if (start >= data.length) {
      out.add(Uint8List(chunkSize));
    } else {
      final end = (start + chunkSize).clamp(0, data.length);
      out.add(data.sublist(start, end));
      final pad = chunkSize - (end - start);
      if (pad > 0) out.add(Uint8List(pad));
    }
  }

  /// Convenience: encodes raw PCM16 bytes (little-endian, mono) to VAG blocks.
  static Uint8List encodeBytes(Uint8List pcmBytes) =>
      encode(Int16List.sublistView(pcmBytes));
}
