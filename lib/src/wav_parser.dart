import 'dart:typed_data';

/// Parses a RIFF/WAV file and exposes mono PCM16 samples and per-channel data.
///
/// Supported input formats:
///   PCM16       (format 0x0001, 16-bit)
///   PCM24       (format 0x0001, 24-bit)
///   PCM32       (format 0x0001, 32-bit integer)
///   IEEE float  (format 0x0003, 32-bit float)
///
/// [samples] is a mono mix of all input channels (existing API, unchanged).
/// [channelSamples] exposes each channel individually — use for stereo encoding.
class WavParser {
  final Int16List samples;             // mono mix of all channels
  final List<Int16List> channelSamples; // one Int16List per input channel
  final int sampleRate;
  final int channels;

  WavParser._(this.samples, this.channelSamples, this.sampleRate, this.channels);

  /// Returns WAV header fields without decoding sample data.
  ///
  /// Works for any WAV format, including ATRAC3+ and other non-PCM types.
  /// Returns `null` if [bytes] is not a valid RIFF/WAV file or has no `fmt ` chunk.
  static ({int format, int channels, int sampleRate})? readInfo(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (!_cc(bytes, 0, 'RIFF') || !_cc(bytes, 8, 'WAVE')) return null;
    int pos = 12;
    while (pos + 8 <= bytes.length) {
      final tag  = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = _u32(bytes, pos + 4);
      if (tag == 'fmt ') {
        final o = pos + 8;
        return (
          format:     _u16(bytes, o),
          channels:   _u16(bytes, o + 2),
          sampleRate: _u32(bytes, o + 4),
        );
      }
      pos += 8 + size + (size & 1);
    }
    return null;
  }

  static WavParser parse(Uint8List bytes) {
    if (bytes.length < 44) throw const FormatException('File too short');
    if (!_cc(bytes, 0, 'RIFF') || !_cc(bytes, 8, 'WAVE')) {
      throw const FormatException('Not a RIFF/WAVE file');
    }

    // Scan chunks for fmt and data.
    int? fmtOff, dataOff, dataLen;
    int pos = 12;
    while (pos + 8 <= bytes.length) {
      final tag  = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = _u32(bytes, pos + 4);
      if (tag == 'fmt ') fmtOff = pos + 8;
      if (tag == 'data') { dataOff = pos + 8; dataLen = size; }
      pos += 8 + size + (size & 1); // word-align
      if (fmtOff != null && dataOff != null) break;
    }
    if (fmtOff == null) throw const FormatException('No fmt chunk');
    if (dataOff == null) throw const FormatException('No data chunk');

    final format     = _u16(bytes, fmtOff);
    final channels   = _u16(bytes, fmtOff + 2);
    final sampleRate = _u32(bytes, fmtOff + 4);
    final bitDepth   = _u16(bytes, fmtOff + 14);

    if (format != 0x0001 && format != 0x0003) {
      throw FormatException(
          'Unsupported WAV format 0x${format.toRadixString(16).padLeft(4, "0")} '
          '— supply PCM (0x0001) or IEEE float (0x0003)');
    }

    final end  = (dataOff + dataLen!).clamp(0, bytes.length);
    final data = ByteData.sublistView(bytes, dataOff, end);
    final bps  = bitDepth >> 3; // bytes per sample
    final totalFrames = data.lengthInBytes ~/ (bps * channels);

    // Decode each channel into its own Int16List.
    final chans = List.generate(channels, (_) => Int16List(totalFrames));
    for (int i = 0; i < totalFrames; i++) {
      for (int ch = 0; ch < channels; ch++) {
        final o = (i * channels + ch) * bps;
        final normalized = switch ((format, bitDepth)) {
          (0x0003, _) => data.getFloat32(o, Endian.little),
          (_, 16)     => data.getInt16(o, Endian.little) / 32768.0,
          (_, 24)     => _i24(data, o) / 8388608.0,
          (_, 32)     => data.getInt32(o, Endian.little) / 2147483648.0,
          _           => 0.0,
        };
        chans[ch][i] = (normalized * 32767).round().clamp(-32768, 32767);
      }
    }

    // Mono mix for the `samples` field.
    final Int16List mono;
    if (channels == 1) {
      mono = chans[0];
    } else {
      mono = Int16List(totalFrames);
      for (int i = 0; i < totalFrames; i++) {
        double sum = 0;
        for (int ch = 0; ch < channels; ch++) { sum += chans[ch][i]; }
        mono[i] = (sum / channels).round().clamp(-32768, 32767);
      }
    }

    return WavParser._(mono, List.unmodifiable(chans), sampleRate, channels);
  }

  static bool _cc(Uint8List b, int o, String s) =>
      b[o] == s.codeUnitAt(0) && b[o + 1] == s.codeUnitAt(1) &&
      b[o + 2] == s.codeUnitAt(2) && b[o + 3] == s.codeUnitAt(3);

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static double _i24(ByteData bd, int o) {
    final lo = bd.getUint8(o), mi = bd.getUint8(o + 1), hi = bd.getInt8(o + 2);
    return ((hi << 16) | (mi << 8) | lo).toDouble();
  }
}
