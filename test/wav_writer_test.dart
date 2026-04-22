import 'dart:typed_data';
import 'package:bf_sound_tool/src/wav_writer.dart';
import 'package:test/test.dart';

// Helpers to parse WAV header fields from a Uint8List.
String _fourCC(Uint8List b, int off) =>
    String.fromCharCodes(b.sublist(off, off + 4));

int _u16(Uint8List b, int off) =>
    ByteData.sublistView(b, off, off + 2).getUint16(0, Endian.little);

int _u32(Uint8List b, int off) =>
    ByteData.sublistView(b, off, off + 4).getUint32(0, Endian.little);

void main() {
  // Minimal 48-byte audio payload for header tests.
  final fakeAudio48 = Uint8List(48)..fillRange(0, 48, 0xAB);
  // 18931712 bytes matching hot_amb_wind padded size.
  final fakeAudioStream = Uint8List(18931712);

  group('buildXboxAdpcm — stereo', () {
    late Uint8List wav;
    setUpAll(() => wav = WavWriter.buildXboxAdpcm(fakeAudio48, 44100, 2));

    test('total file size = audioSize + 48 bytes header', () {
      expect(wav.length, equals(48 + 48));
    });

    test('RIFF magic', () => expect(_fourCC(wav, 0), equals('RIFF')));

    test('RIFF chunk size = fileSize - 8', () {
      expect(_u32(wav, 4), equals(wav.length - 8));
    });

    test('WAVE magic', () => expect(_fourCC(wav, 8), equals('WAVE')));
    test('fmt  magic', () => expect(_fourCC(wav, 12), equals('fmt ')));
    test('fmt chunk size = 20 (ADPCM)', () => expect(_u32(wav, 16), equals(20)));
    test('format code = 0x0069 (Xbox ADPCM)', () {
      expect(_u16(wav, 20), equals(0x0069));
    });
    test('channels = 2', () => expect(_u16(wav, 22), equals(2)));
    test('sample rate = 44100', () => expect(_u32(wav, 24), equals(44100)));
    test('byte rate = sampleRate / 2 = 22050', () {
      expect(_u32(wav, 28), equals(22050));
    });
    test('block align = 72 (stereo Xbox ADPCM)', () {
      expect(_u16(wav, 32), equals(72));
    });
    test('bits per sample = 4', () => expect(_u16(wav, 34), equals(4)));
    test('cbSize = 2', () => expect(_u16(wav, 36), equals(2)));
    test('samplesPerBlock = 64', () => expect(_u16(wav, 38), equals(64)));
    test('data magic', () => expect(_fourCC(wav, 40), equals('data')));
    test('data chunk size = audio length', () {
      expect(_u32(wav, 44), equals(48));
    });
    test('audio payload starts at offset 48', () {
      expect(wav.sublist(48), equals(fakeAudio48));
    });
  });

  group('buildXboxAdpcm — mono', () {
    late Uint8List wav;
    setUpAll(() => wav = WavWriter.buildXboxAdpcm(fakeAudio48, 22050, 1));

    test('format code = 0x0069', () => expect(_u16(wav, 20), equals(0x0069)));
    test('channels = 1', () => expect(_u16(wav, 22), equals(1)));
    test('block align = 36 (mono Xbox ADPCM)', () {
      expect(_u16(wav, 32), equals(36));
    });
    test('byte rate = 22050 / 2 = 11025', () {
      expect(_u32(wav, 28), equals(11025));
    });
  });

  group('VB output size parity — hot_amb_wind stereo stream', () {
    // VB output: audioReadSize + 48 = 18931712 + 48 = 18931760
    test('output length = audioReadSize + 48 (matches VB file size)', () {
      final wav = WavWriter.buildXboxAdpcm(fakeAudioStream, 44100, 2);
      expect(wav.length, equals(18931712 + 48));
    });
  });

  group('buildPcm16', () {
    late Uint8List wav;
    setUpAll(() => wav = WavWriter.buildPcm16(fakeAudio48, 22050, 1));

    test('format code = 0x0001 (PCM)', () => expect(_u16(wav, 20), equals(1)));
    test('fmt chunk size = 16', () => expect(_u32(wav, 16), equals(16)));
    test('block align = 2', () => expect(_u16(wav, 32), equals(2)));
    test('bits per sample = 16', () => expect(_u16(wav, 34), equals(16)));
    test('data magic at offset 36', () => expect(_fourCC(wav, 36), equals('data')));
    test('total file size = audioSize + 44', () {
      expect(wav.length, equals(48 + 44));
    });
  });
}
