import 'dart:typed_data';
import 'package:sound_ripper/src/amb_deinterlacer.dart';
import 'package:test/test.dart';

/// Build a synthetic 2-channel PCM16 buffer with [chunkCount] chunk pairs.
///
/// Stream 1 frames fill with value [s1], stream 2 frames fill with [s2].
/// Each chunk is [AmbDeinterlacer.interlaceSampleCount] stereo frames.
Uint8List _makeSyntheticPcm(int chunkCount, {int s1 = 0x1111, int s2 = 0x2222}) {
  final n = AmbDeinterlacer.interlaceSampleCount;
  // Each chunk pair: n stereo frames of s1 + n stereo frames of s2
  // Each stereo frame = 2 int16 = 4 bytes
  final buf = Uint8List(chunkCount * n * 2 * 4);
  final w = buf.buffer.asUint16List();
  for (int chunk = 0; chunk < chunkCount; chunk++) {
    final base = chunk * n * 2 * 2; // in u16 words: 2 streams × n frames × 2 words
    // stream 1 chunk: n frames × 2 words
    for (int i = 0; i < n; i++) {
      w[base + i * 2]     = s1;
      w[base + i * 2 + 1] = s1 + 1;
    }
    // stream 2 chunk immediately after
    final s2Base = base + n * 2;
    for (int i = 0; i < n; i++) {
      w[s2Base + i * 2]     = s2;
      w[s2Base + i * 2 + 1] = s2 + 1;
    }
  }
  return buf;
}

void main() {
  const n = AmbDeinterlacer.interlaceSampleCount;
  const bytesPerFrame = 4; // 2 ch × 2 bytes

  group('AmbDeinterlacer — single chunk', () {
    late Uint8List fnt;
    late Uint8List bck;

    setUpAll(() {
      final pcm = _makeSyntheticPcm(1);
      (fnt, bck) = AmbDeinterlacer.deinterlace(pcm);
    });

    test('front output length = interlaceSampleCount × 4 bytes', () {
      expect(fnt.length, equals(n * bytesPerFrame));
    });

    test('back output length = interlaceSampleCount × 4 bytes', () {
      expect(bck.length, equals(n * bytesPerFrame));
    });

    test('front first word = stream1 value', () {
      expect(fnt.buffer.asUint16List()[0], equals(0x1111));
    });

    test('front second word = stream1 value + 1', () {
      expect(fnt.buffer.asUint16List()[1], equals(0x1112));
    });

    test('back first word = stream2 value', () {
      expect(bck.buffer.asUint16List()[0], equals(0x2222));
    });

    test('back second word = stream2 value + 1', () {
      expect(bck.buffer.asUint16List()[1], equals(0x2223));
    });

    test('front all frames equal stream1 values', () {
      final w = fnt.buffer.asUint16List();
      for (int i = 0; i < n; i++) {
        expect(w[i * 2],     equals(0x1111), reason: 'frame $i L');
        expect(w[i * 2 + 1], equals(0x1112), reason: 'frame $i R');
      }
    });

    test('back all frames equal stream2 values', () {
      final w = bck.buffer.asUint16List();
      for (int i = 0; i < n; i++) {
        expect(w[i * 2],     equals(0x2222), reason: 'frame $i L');
        expect(w[i * 2 + 1], equals(0x2223), reason: 'frame $i R');
      }
    });
  });

  group('AmbDeinterlacer — multiple chunks', () {
    const chunkCount = 3;
    late Uint8List fnt;
    late Uint8List bck;

    setUpAll(() {
      final pcm = _makeSyntheticPcm(chunkCount);
      (fnt, bck) = AmbDeinterlacer.deinterlace(pcm);
    });

    test('output length = chunkCount × interlaceSampleCount × 4', () {
      expect(fnt.length, equals(chunkCount * n * bytesPerFrame));
      expect(bck.length, equals(chunkCount * n * bytesPerFrame));
    });

    test('front + back total output equals half input', () {
      final pcm = _makeSyntheticPcm(chunkCount);
      expect(fnt.length + bck.length, equals(pcm.length));
    });
  });

  group('AmbDeinterlacer — error cases', () {
    test('throws on non-multiple-of-4 length', () {
      expect(
        () => AmbDeinterlacer.deinterlace(Uint8List(6)),
        throwsArgumentError,
      );
    });

    test('throws when combined frame count not divisible by interlaceSampleCount', () {
      // 8 stereo frames → combined = 4 frames, not divisible by 33280
      expect(
        () => AmbDeinterlacer.deinterlace(Uint8List(8 * bytesPerFrame)),
        throwsArgumentError,
      );
    });
  });
}
