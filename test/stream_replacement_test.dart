import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:bf_sound_tool/bf_sound_tool.dart';
import 'package:test/test.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Int16List _sine(int length, double freq, int sampleRate, {int amplitude = 16000}) {
  final out = Int16List(length);
  for (int i = 0; i < length; i++) {
    out[i] = (sin(2 * pi * freq * i / sampleRate) * amplitude).round();
  }
  return out;
}

double _snrDb(Int16List ref, Int16List out) {
  double sig = 0, noise = 0;
  final n = min(ref.length, out.length);
  for (int i = 0; i < n; i++) {
    sig   += ref[i].toDouble() * ref[i];
    final e = ref[i] - out[i];
    noise += e * e;
  }
  if (noise == 0) return double.infinity;
  return 10 * log(sig / noise) / ln10;
}

/// Builds a minimal RIFF/WAV in memory with the given PCM16 channels.
Uint8List _buildWav(List<Int16List> channels, int sampleRate) {
  final numChannels = channels.length;
  final numFrames   = channels[0].length;
  final byteRate    = sampleRate * numChannels * 2;
  final dataBytes   = numFrames * numChannels * 2;

  final buf = BytesBuilder();
  void u32(int v) => buf.add([v & 0xFF, (v>>8)&0xFF, (v>>16)&0xFF, (v>>24)&0xFF]);
  void u16(int v) => buf.add([v & 0xFF, (v>>8)&0xFF]);
  void tag(String s) => buf.add(s.codeUnits);

  tag('RIFF'); u32(36 + dataBytes); tag('WAVE');
  tag('fmt '); u32(16);
  u16(0x0001); u16(numChannels); u32(sampleRate);
  u32(byteRate); u16(numChannels * 2); u16(16);
  tag('data'); u32(dataBytes);
  final bd = ByteData(dataBytes);
  for (int i = 0; i < numFrames; i++) {
    for (int ch = 0; ch < numChannels; ch++) {
      bd.setInt16((i * numChannels + ch) * 2, channels[ch][i], Endian.little);
    }
  }
  buf.add(bd.buffer.asUint8List());
  return buf.toBytes();
}

// ── WavParser stereo ──────────────────────────────────────────────────────────

void main() {
  group('WavParser — stereo channelSamples', () {
    const sampleRate = 22050;
    const frames = 1000;
    late Int16List leftIn, rightIn;
    late WavParser parsed;

    setUpAll(() {
      leftIn  = _sine(frames, 440.0,  sampleRate);
      rightIn = _sine(frames, 880.0,  sampleRate);
      final wavBytes = _buildWav([leftIn, rightIn], sampleRate);
      parsed = WavParser.parse(wavBytes);
    });

    test('channels == 2', () => expect(parsed.channels, 2));
    test('channelSamples has 2 entries', () => expect(parsed.channelSamples.length, 2));

    test('left channel matches input', () {
      expect(_snrDb(leftIn, parsed.channelSamples[0]), greaterThan(90.0),
          reason: 'Left channel should survive PCM round-trip losslessly');
    });

    test('right channel matches input', () {
      expect(_snrDb(rightIn, parsed.channelSamples[1]), greaterThan(90.0),
          reason: 'Right channel should survive PCM round-trip losslessly');
    });

    test('samples is mono mix of both channels', () {
      final mono = Int16List.fromList(List.generate(
          frames, (i) => ((leftIn[i] + rightIn[i]) / 2).round().clamp(-32768, 32767)));
      expect(_snrDb(mono, parsed.samples), greaterThan(90.0));
    });

    test('mono WAV has channelSamples.length == 1', () {
      final mono = _sine(frames, 440.0, sampleRate);
      final wav = _buildWav([mono], sampleRate);
      final p = WavParser.parse(wav);
      expect(p.channelSamples.length, 1);
      expect(p.channels, 1);
    });
  });

  // ── Xbox ADPCM stereo round-trip ─────────────────────────────────────────

  group('XboxAdpcmEncoder — stereo round-trip', () {
    const sampleRate = 22050;
    const frames = 22050; // 1 second
    late Int16List left, right;
    late Uint8List encoded;
    late Uint8List decoded;

    setUpAll(() {
      left    = _sine(frames, 440.0, sampleRate);
      right   = _sine(frames, 880.0, sampleRate);
      encoded = XboxAdpcmEncoder.encodeStereo(left, right);
      decoded = XboxAdpcmDecoder.decode(encoded, 2);
    });

    test('block count correct (blockAlign 72)', () {
      final blocks = (frames + 64) ~/ 65;
      expect(encoded.length, blocks * 72);
    });

    test('decoded length covers input', () {
      final expectedFrames = ((frames + 64) ~/ 65) * 65;
      // decoded is interleaved L/R → total Int16 count = expectedFrames * 2
      expect(decoded.length ~/ 4, greaterThanOrEqualTo(frames));
      expect(decoded.length ~/ 4, expectedFrames);
    });

    test('left channel SNR ≥ 28 dB', () {
      final decoded16 = Int16List.sublistView(decoded);
      final decL = Int16List.fromList(
          List.generate(frames, (i) => decoded16[i * 2]));
      expect(_snrDb(left, decL), greaterThan(28.0));
    });

    test('right channel SNR ≥ 28 dB', () {
      final decoded16 = Int16List.sublistView(decoded);
      final decR = Int16List.fromList(
          List.generate(frames, (i) => decoded16[i * 2 + 1]));
      expect(_snrDb(right, decR), greaterThan(28.0));
    });

    test('stereo channels are distinct', () {
      final decoded16 = Int16List.sublistView(decoded);
      final decL = Int16List.fromList(List.generate(frames, (i) => decoded16[i * 2]));
      final decR = Int16List.fromList(List.generate(frames, (i) => decoded16[i * 2 + 1]));
      // L and R should differ significantly (different frequencies).
      final lrDiff = List.generate(frames, (i) => (decL[i] - decR[i]).abs())
          .reduce(max);
      expect(lrDiff, greaterThan(1000));
    });
  });

  // ── VagEncoder stereo PS2 interleave ─────────────────────────────────────

  group('VagEncoder.encodeStereoPs2 — interleave layout', () {
    const chunkSize = 16384;
    const sampleRate = 22050;
    const frames = 22050;
    late Int16List left, right;
    late Uint8List interleaved;

    setUpAll(() {
      left        = _sine(frames, 440.0, sampleRate);
      right       = _sine(frames, 880.0, sampleRate);
      interleaved = VagEncoder.encodeStereoPs2(left, right, chunkSize);
    });

    test('total size is multiple of chunkSize', () {
      expect(interleaved.length % chunkSize, 0);
    });

    test('size is 2× (one L chunk + one R chunk) per group', () {
      // Each "group" in the interleaved stream is [chunkSize L][chunkSize R].
      expect(interleaved.length % (chunkSize * 2), 0);
    });

    test('decoding round-trip: L channel SNR ≥ 30 dB', () {
      final decoded = VagDecoder.decode(interleaved, 2, chunkSize);
      final decoded16 = Int16List.sublistView(decoded);
      final decL = Int16List.fromList(List.generate(frames, (i) => decoded16[i * 2]));
      expect(_snrDb(left, decL), greaterThan(30.0));
    });

    test('decoding round-trip: R channel SNR ≥ 30 dB', () {
      final decoded = VagDecoder.decode(interleaved, 2, chunkSize);
      final decoded16 = Int16List.sublistView(decoded);
      final decR = Int16List.fromList(List.generate(frames, (i) => decoded16[i * 2 + 1]));
      expect(_snrDb(right, decR), greaterThan(30.0));
    });
  });

  // ── Xbox stream replacement end-to-end ───────────────────────────────────

  group('Xbox stereo stream replacement', () {
    const xboxFile = 'test/test_files/xbox/hot.lvl';
    const sampleRate = 22050;
    const frames = 22050; // 1 second

    late Uint8List origBytes;
    late BattlefrontSoundFile sf;
    late SoundRecord streamRecord; // first stereo stream in the file

    setUpAll(() {
      origBytes = File(xboxFile).readAsBytesSync();
      sf = BattlefrontSoundFile(origBytes, 'xbox', 'bf2');
      streamRecord = sf.getAllSounds()
          .firstWhere((r) => r.isStream && r.channels == 2 && !r.skip);
    });

    test('test file has at least one stereo stream', () {
      expect(streamRecord, isNotNull);
    });

    test('replaced stereo stream round-trips with SNR ≥ 28 dB (L channel)', () {
      final left  = _sine(frames, 440.0, sampleRate);
      final right = _sine(frames, 880.0, sampleRate);
      final encoded = XboxAdpcmEncoder.encodeStereo(left, right);

      final outBytes = sf.replaceAudio(streamRecord, encoded,
          newSampleRate: sampleRate);
      final outSf = BattlefrontSoundFile(outBytes, 'xbox', 'bf2');
      final outRecord = outSf.getSound(streamRecord.name)!;

      expect(outRecord.dataSize, encoded.length);
      expect(outRecord.sampleRate, sampleRate);

      // Decode back and measure quality.
      final raw     = outSf.extractRawAudio(outRecord);
      final decoded = XboxAdpcmDecoder.decode(raw, 2);
      final dec16   = Int16List.sublistView(decoded);
      final decL    = Int16List.fromList(List.generate(frames, (i) => dec16[i * 2]));
      expect(_snrDb(left, decL), greaterThan(28.0));
    });

    test('replaced stereo stream round-trips with SNR ≥ 28 dB (R channel)', () {
      final left  = _sine(frames, 440.0, sampleRate);
      final right = _sine(frames, 880.0, sampleRate);
      final encoded = XboxAdpcmEncoder.encodeStereo(left, right);

      final outBytes = sf.replaceAudio(streamRecord, encoded,
          newSampleRate: sampleRate);
      final outSf = BattlefrontSoundFile(outBytes, 'xbox', 'bf2');
      final outRecord = outSf.getSound(streamRecord.name)!;

      final raw     = outSf.extractRawAudio(outRecord);
      final decoded = XboxAdpcmDecoder.decode(raw, 2);
      final dec16   = Int16List.sublistView(decoded);
      final decR    = Int16List.fromList(List.generate(frames, (i) => dec16[i * 2 + 1]));
      expect(_snrDb(right, decR), greaterThan(28.0));
    });

    test('other entries audio data is not affected', () {
      final left  = _sine(frames, 440.0, sampleRate);
      final right = _sine(frames, 880.0, sampleRate);
      final encoded = XboxAdpcmEncoder.encodeStereo(left, right);
      final outBytes = sf.replaceAudio(streamRecord, encoded,
          newSampleRate: sampleRate);
      final outSf = BattlefrontSoundFile(outBytes, 'xbox', 'bf2');

      // Find another active entry and compare its data bytes (not padding).
      final other = sf.getAllSounds()
          .where((r) => !r.skip && r.name != streamRecord.name)
          .first;
      final otherOut = outSf.getSound(other.name)!;
      // Compare dataSize bytes only — padding bytes may become 0 when bank is rebuilt.
      final origData = Uint8List.sublistView(sf.extractRawAudio(other), 0, other.dataSize);
      final outData  = Uint8List.sublistView(outSf.extractRawAudio(otherOut), 0, otherOut.dataSize);
      expect(outData, equals(origData));
    });
  });

  // ── PS2 stereo stream replacement end-to-end ─────────────────────────────

  group('PS2 stereo stream replacement', () {
    const ps2File = 'test/test_files/ps2/HOT.LVL';
    const sampleRate = 22050;
    const frames = 22050; // 1 second

    late Uint8List origBytes;
    late BattlefrontSoundFile sf;
    late SoundRecord streamRecord;

    setUpAll(() {
      origBytes = File(ps2File).readAsBytesSync();
      sf = BattlefrontSoundFile(origBytes, 'ps2', 'bf2');
      streamRecord = sf.getAllSounds()
          .firstWhere((r) => r.isStream && r.channels == 2 && !r.skip);
    });

    test('test file has at least one stereo stream', () {
      expect(streamRecord, isNotNull);
    });

    test('replaced PS2 stereo stream round-trips (L channel SNR ≥ 30 dB)', () {
      final left  = _sine(frames, 440.0, sampleRate);
      final right = _sine(frames, 880.0, sampleRate);
      final encoded = VagEncoder.encodeStereoPs2(
          left, right, streamRecord.substreamInterleave);

      final outBytes = sf.replaceAudio(streamRecord, encoded,
          newSampleRate: sampleRate);
      final outSf = BattlefrontSoundFile(outBytes, 'ps2', 'bf2');
      final outRecord = outSf.getSound(streamRecord.name)!;

      expect(outRecord.sampleRate, sampleRate);

      final raw     = outSf.extractRawAudio(outRecord);
      final decoded = VagDecoder.decode(raw, 2, outRecord.substreamInterleave);
      final dec16   = Int16List.sublistView(decoded);
      final decL    = Int16List.fromList(List.generate(frames, (i) => dec16[i * 2]));
      expect(_snrDb(left, decL), greaterThan(30.0));
    });

    test('replaced PS2 stereo stream round-trips (R channel SNR ≥ 30 dB)', () {
      final left  = _sine(frames, 440.0, sampleRate);
      final right = _sine(frames, 880.0, sampleRate);
      final encoded = VagEncoder.encodeStereoPs2(
          left, right, streamRecord.substreamInterleave);

      final outBytes = sf.replaceAudio(streamRecord, encoded,
          newSampleRate: sampleRate);
      final outSf = BattlefrontSoundFile(outBytes, 'ps2', 'bf2');
      final outRecord = outSf.getSound(streamRecord.name)!;

      final raw     = outSf.extractRawAudio(outRecord);
      final decoded = VagDecoder.decode(raw, 2, outRecord.substreamInterleave);
      final dec16   = Int16List.sublistView(decoded);
      final decR    = Int16List.fromList(List.generate(frames, (i) => dec16[i * 2 + 1]));
      expect(_snrDb(right, decR), greaterThan(30.0));
    });
  });

  // ── WavParser.readInfo ────────────────────────────────────────────────────

  group('WavParser.readInfo', () {
    test('returns sampleRate from a PCM WAV', () {
      final wav = _buildWav([_sine(100, 440.0, 22050)], 22050);
      final info = WavParser.readInfo(wav);
      expect(info, isNotNull);
      expect(info!.sampleRate, 22050);
      expect(info.channels, 1);
      expect(info.format, 0x0001); // PCM
    });

    test('returns sampleRate from a non-PCM (simulated at3plus) WAV', () {
      // Build a minimal WAV with format 0xFFFE (WAVE_FORMAT_EXTENSIBLE, used by at3plus).
      final buf = BytesBuilder();
      void u32(int v) => buf.add([v&0xFF,(v>>8)&0xFF,(v>>16)&0xFF,(v>>24)&0xFF]);
      void u16(int v) => buf.add([v&0xFF,(v>>8)&0xFF]);
      void tag(String s) => buf.add(s.codeUnits);
      const sr = 44100;
      tag('RIFF'); u32(36 + 4); tag('WAVE');
      tag('fmt '); u32(16);
      u16(0xFFFE); u16(2); u32(sr); // format=extensible, 2ch, 44100
      u32(sr * 4); u16(4); u16(16);
      tag('data'); u32(4); buf.add([0,0,0,0]);
      final info = WavParser.readInfo(buf.toBytes());
      expect(info, isNotNull);
      expect(info!.format, 0xFFFE);
      expect(info.sampleRate, sr);
      expect(info.channels, 2);
    });

    test('returns null for non-WAV bytes', () {
      expect(WavParser.readInfo(Uint8List(64)), isNull);
    });
  });

  // ── PSP stream passthrough ────────────────────────────────────────────────

  group('PSP stream passthrough', () {
    const pspFile = 'test/test_files/psp/gal.lvl';

    late Uint8List origBytes;
    late BattlefrontSoundFile sf;
    late SoundRecord target;
    late Uint8List replacementRaw; // at3plus WAV bytes from another stream

    setUpAll(() {
      origBytes = File(pspFile).readAsBytesSync();
      sf = BattlefrontSoundFile(origBytes, 'psp', 'bf2');
      final streams = sf.getAllSounds()
          .where((r) => r.isStream && !r.skip)
          .toList();
      target          = streams[0];
      replacementRaw  = sf.extractRawAudio(streams[1]);
    });

    test('replaced PSP stream stores raw bytes unchanged', () {
      final outBytes = sf.replaceAudio(target, replacementRaw);
      final outSf    = BattlefrontSoundFile(outBytes, 'psp', 'bf2');
      final outRecord = outSf.getSound(target.name)!;
      expect(outSf.extractRawAudio(outRecord), equals(replacementRaw));
    });

    test('dataSize updated to replacement length', () {
      final outBytes = sf.replaceAudio(target, replacementRaw);
      final outSf    = BattlefrontSoundFile(outBytes, 'psp', 'bf2');
      final outRecord = outSf.getSound(target.name)!;
      expect(outRecord.dataSize, replacementRaw.length);
    });

    test('WavParser.readInfo reads sampleRate from extracted at3plus WAV', () {
      final info = WavParser.readInfo(replacementRaw);
      expect(info, isNotNull);
      expect(info!.sampleRate, greaterThan(0));
    });
  });

  // ── PC stream replacement end-to-end ─────────────────────────────────────

  group('PC stream replacement', () {
    const pcFile = 'test/test_files/pc/hot.lvl';
    const sampleRate = 22050;
    const frames = 22050;

    late Uint8List origBytes;
    late BattlefrontSoundFile sf;
    late SoundRecord streamRecord;

    setUpAll(() {
      origBytes = File(pcFile).readAsBytesSync();
      sf = BattlefrontSoundFile(origBytes, 'pc', 'bf2');
      // PC streams may be mono or stereo — take first stream.
      streamRecord = sf.getAllSounds()
          .firstWhere((r) => r.isStream && !r.skip);
    });

    test('test file has at least one stream', () {
      expect(streamRecord, isNotNull);
    });

    test('replaced PC mono stream round-trips with SNR ≥ 28 dB', () {
      final mono    = _sine(frames, 440.0, sampleRate);
      final encoded = XboxAdpcmEncoder.encode(mono);

      final outBytes = sf.replaceAudio(streamRecord, encoded,
          newSampleRate: sampleRate);
      final outSf    = BattlefrontSoundFile(outBytes, 'pc', 'bf2');
      final outRecord = outSf.getSound(streamRecord.name)!;

      expect(outRecord.dataSize, encoded.length);
      expect(outRecord.sampleRate, sampleRate);

      final raw     = outSf.extractRawAudio(outRecord);
      // Decode as mono (even if original was stereo — we encoded mono)
      final decoded = XboxAdpcmDecoder.decode(raw, 1);
      final dec16   = Int16List.sublistView(decoded);
      expect(_snrDb(mono, dec16), greaterThan(28.0));
    });
  });
}
