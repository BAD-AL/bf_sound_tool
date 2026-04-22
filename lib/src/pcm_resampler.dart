import 'dart:typed_data';

/// Linear-interpolation PCM16 resampler.
class PcmResampler {
  /// Resamples mono signed-16 [samples] from [srcRate] to [dstRate] Hz.
  static Int16List resample(Int16List samples, int srcRate, int dstRate) {
    if (srcRate == dstRate) return samples;
    final ratio = srcRate / dstRate;
    final outLen = (samples.length / ratio).ceil();
    final out = Int16List(outLen);
    for (int i = 0; i < outLen; i++) {
      final pos = i * ratio;
      final idx = pos.floor();
      final frac = pos - idx;
      final s0 = samples[idx].toDouble();
      final s1 = idx + 1 < samples.length ? samples[idx + 1].toDouble() : s0;
      out[i] = (s0 + (s1 - s0) * frac).round().clamp(-32768, 32767);
    }
    return out;
  }
}
