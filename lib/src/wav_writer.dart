import 'dart:typed_data';

/// Builds WAV file headers matching VB SoundRipperVB output.
class WavWriter {
  // WAV format codes
  static const int fmtPcm16 = 0x0001;
  static const int fmtImaAdpcm = 0x0011;
  static const int fmtXboxAdpcm = 0x0069;

  /// Build a complete WAV file (header + [audioData]) for a plain PCM-16 bank.
  ///
  /// Used for .bnk / non-stream files where format is standard PCM16.
  static Uint8List buildPcm16(
    Uint8List audioData,
    int sampleRate,
    int channels,
  ) {
    final dataSize = audioData.length;
    // RIFF chunk size = total file size - 8 = (44 header + dataSize) - 8
    final riffSize = dataSize + 36;
    final byteRate = sampleRate * 2; // sampleRate * blockAlign(2)

    final header = ByteData(44);
    var off = 0;
    // RIFF
    _setFourCC(header, off, 'RIFF'); off += 4;
    header.setUint32(off, riffSize, Endian.little); off += 4;
    // WAVE
    _setFourCC(header, off, 'WAVE'); off += 4;
    // fmt  (chunk size 16 for PCM)
    _setFourCC(header, off, 'fmt '); off += 4;
    header.setUint32(off, 16, Endian.little); off += 4;
    header.setUint16(off, fmtPcm16, Endian.little); off += 2;
    header.setUint16(off, channels, Endian.little); off += 2;
    header.setUint32(off, sampleRate, Endian.little); off += 4;
    header.setUint32(off, byteRate, Endian.little); off += 4;
    header.setUint16(off, 2, Endian.little); off += 2; // blockAlign
    header.setUint16(off, 16, Endian.little); off += 2; // bitsPerSample
    // data
    _setFourCC(header, off, 'data'); off += 4;
    header.setUint32(off, dataSize, Endian.little);

    return _concat(header.buffer.asUint8List(), audioData);
  }

  /// Build a WAV file for Xbox ADPCM (format 0x0069), matching VB wavxPCM output.
  ///
  /// Used for Xbox .lvl stream and sample files.
  static Uint8List buildXboxAdpcm(
    Uint8List audioData,
    int sampleRate,
    int channels,
  ) {
    final dataSize = audioData.length;
    // RIFF chunk size = total file size - 8 = (48 header + dataSize) - 8
    final riffSize = dataSize + 40;
    final byteRate = sampleRate ~/ 2;

    // Block alignment: 36 bytes mono, 72 bytes stereo (Xbox ADPCM spec)
    final blockAlign = channels == 2 ? 72 : 36;
    // Bits per sample: always 4 for ADPCM
    const bitsPerSample = 4;
    // Samples per block: derived from block align
    // VB uses fixed value 64 (0x40) in wavheader3
    const samplesPerBlock = 64;

    final header = ByteData(48);
    var off = 0;
    // RIFF
    _setFourCC(header, off, 'RIFF'); off += 4;
    header.setUint32(off, riffSize, Endian.little); off += 4;
    // WAVE
    _setFourCC(header, off, 'WAVE'); off += 4;
    // fmt  (chunk size 20 for ADPCM)
    _setFourCC(header, off, 'fmt '); off += 4;
    header.setUint32(off, 20, Endian.little); off += 4;
    header.setUint16(off, fmtXboxAdpcm, Endian.little); off += 2;
    header.setUint16(off, channels, Endian.little); off += 2;
    header.setUint32(off, sampleRate, Endian.little); off += 4;
    header.setUint32(off, byteRate, Endian.little); off += 4;
    header.setUint16(off, blockAlign, Endian.little); off += 2;
    header.setUint16(off, bitsPerSample, Endian.little); off += 2;
    // cbSize (extra bytes in fmt): 2
    header.setUint16(off, 2, Endian.little); off += 2;
    // samplesPerBlock
    header.setUint16(off, samplesPerBlock, Endian.little); off += 2;
    // data
    _setFourCC(header, off, 'data'); off += 4;
    header.setUint32(off, dataSize, Endian.little);

    return _concat(header.buffer.asUint8List(), audioData);
  }

  static void _setFourCC(ByteData bd, int offset, String s) {
    for (int i = 0; i < 4; i++) {
      bd.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  static Uint8List _concat(Uint8List a, Uint8List b) {
    final result = Uint8List(a.length + b.length);
    result.setAll(0, a);
    result.setAll(a.length, b);
    return result;
  }
}
