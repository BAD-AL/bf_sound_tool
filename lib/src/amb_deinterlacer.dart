import 'dart:typed_data';

/// Deinterleaves a 4-channel (2-stream stereo) PCM16 audio buffer.
///
/// BF2 ambient streams store two stereo streams interleaved in chunks of
/// [interlaceSampleCount] sample frames.  Layout in the raw buffer:
///
///   [stream1 chunk 0: N*2 int16s] [stream2 chunk 0: N*2 int16s]
///   [stream1 chunk 1: N*2 int16s] [stream2 chunk 1: N*2 int16s]  …
///
/// Returns (front, back) as separate stereo PCM16 byte arrays.
class AmbDeinterlacer {
  static const int interlaceSampleCount = 33280;

  /// Deinterleave [pcm16] (stereo PCM16, no WAV header) into front and back
  /// stereo byte arrays.  Throws [ArgumentError] if dimensions don't fit.
  static (Uint8List front, Uint8List back) deinterlace(Uint8List pcm16) {
    // 2 bytes per sample × 2 channels = 4 bytes per stereo frame
    const bytesPerFrame = 4;
    if (pcm16.length % bytesPerFrame != 0) {
      throw ArgumentError('PCM16 buffer length must be a multiple of 4');
    }

    final totalFrames = pcm16.length ~/ bytesPerFrame;
    if (totalFrames % 2 != 0) {
      throw ArgumentError('Total frame count must be divisible by 2');
    }

    final combinedFrames = totalFrames ~/ 2;
    final chunkCount = combinedFrames ~/ interlaceSampleCount;
    if (chunkCount * interlaceSampleCount != combinedFrames) {
      throw ArgumentError(
        'Combined frame count $combinedFrames is not divisible by '
        'interlaceSampleCount $interlaceSampleCount',
      );
    }

    final fnt = Uint8List(combinedFrames * bytesPerFrame);
    final bck = Uint8List(combinedFrames * bytesPerFrame);

    // View as int16 words for direct index arithmetic.
    final src = pcm16.buffer.asUint16List(pcm16.offsetInBytes, pcm16.length ~/ 2);
    final fntW = fnt.buffer.asUint16List();
    final bckW = bck.buffer.asUint16List();

    // Each chunk has interlaceSampleCount stereo frames (2 int16s each).
    const stereoWords = 2; // words per stereo frame
    final chunkWords = interlaceSampleCount * stereoWords;      // stream1 size
    final chunkStride = chunkWords * 2;                         // stream1 + stream2

    int writeOffset = 0;
    int srcOffset = 0;

    for (int chunk = 0; chunk < chunkCount; chunk++) {
      for (int i = 0; i < interlaceSampleCount; i++) {
        fntW[writeOffset]     = src[srcOffset];
        fntW[writeOffset + 1] = src[srcOffset + 1];
        bckW[writeOffset]     = src[srcOffset + chunkWords];
        bckW[writeOffset + 1] = src[srcOffset + chunkWords + 1];
        writeOffset += stereoWords;
        srcOffset   += stereoWords;
      }
      // Advance past stream2's chunk (already consumed stream1 above).
      srcOffset += chunkWords;
      assert(srcOffset == (chunk + 1) * chunkStride);
    }

    return (fnt, bck);
  }
}
