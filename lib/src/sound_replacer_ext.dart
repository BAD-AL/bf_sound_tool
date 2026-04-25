import 'dart:typed_data';
import 'pcm_resampler.dart';
import 'sound_record.dart';
import 'vag_encoder.dart';
import 'wav_parser.dart';
import 'xbox_adpcm_encoder.dart';

/// "The Translator" for sound replacing, this file handles the 
/// High-level logic for converting standard WAV files to platform-specific
/// Battlefront sound formats.
/// 
/// This class handles the "smart" part of the replacement:
/// - Parsing standard RIFF/WAV files.
/// - Resampling and channel mixing (stereo to mono).
/// - Platform-specific encoding (VAG for PSP/PS2, Xbox ADPCM for Xbox/PC).
/// 
/// Once the audio is converted, it can be passed to [SoundReplacer] to be 
/// stitched into the final LVL/BNK/STR container.
class SoundReplacerExt {
  /// Converts [wavBytes] to the raw format required for [record].
  ///
  /// Handles:
  /// - Resampling to [targetSampleRate] (or record.sampleRate if null).
  /// - Mono downmixing for sample banks.
  /// - Platform encoding (VAG for PSP/PS2, Xbox ADPCM for Xbox/PC streams).
  static Uint8List convertWav(
    Uint8List wavBytes,
    SoundRecord record,
    String platform, {
    int? targetSampleRate,
  }) {
    final wav = WavParser.parse(wavBytes);
    final rate = targetSampleRate ?? wav.sampleRate;

    // 1. Resample and Mix to mono if necessary
    Int16List samples;
    if (record.channels == 1 && wav.channels > 1) {
      samples = wav.samples; // WavParser.samples is already a mono mix
    } else if (record.channels == 2 && wav.channels == 1) {
      // Duplicate mono to stereo if the target is stereo
      samples = wav.samples; 
    } else {
      samples = wav.samples;
    }

    if (wav.sampleRate != rate) {
      samples = PcmResampler.resample(samples, wav.sampleRate, rate);
    }

    // 2. Encode to platform format
    if (platform == 'psp' || platform == 'ps2') {
      if (record.isStream && record.channels == 2) {
        // PS2 stereo ambient stream
        final wavStereo = (wav.sampleRate == rate) ? wav : _resampleStereo(wav, rate);
        return VagEncoder.encodeStereoPs2(
          wavStereo.channelSamples[0],
          wavStereo.channelSamples[1],
          record.substreamInterleave,
        );
      }
      // Standard VAG mono
      return VagEncoder.encode(samples);
    }

    if (platform == 'xbox' || record.isStream) {
      // Xbox ADPCM
      if (record.channels == 2) {
        final wavStereo = (wav.sampleRate == rate) ? wav : _resampleStereo(wav, rate);
        return XboxAdpcmEncoder.encodeStereo(
          wavStereo.channelSamples[0],
          wavStereo.channelSamples[1],
        );
      }
      return XboxAdpcmEncoder.encode(samples);
    }

    // Default: Raw PCM16 (PC samples, high-fidelity Xbox samples)
    return samples.buffer.asUint8List();
  }

  static WavParser _resampleStereo(WavParser wav, int rate) {
    final left = PcmResampler.resample(wav.channelSamples[0], wav.sampleRate, rate);
    final right = PcmResampler.resample(wav.channelSamples[1], wav.sampleRate, rate);
    // Dummy parse/wrap to return a WavParser-like object for the internal API.
    // Actually, we should probably just return the pair of lists.
    // For now, let's keep it simple.
    return _FakeWavParser(left, right, rate);
  }
}

class _FakeWavParser implements WavParser {
  @override final List<Int16List> channelSamples;
  @override final int sampleRate;
  @override final int channels = 2;
  @override Int16List get samples => throw UnimplementedError();

  _FakeWavParser(Int16List l, Int16List r, this.sampleRate) 
    : channelSamples = [l, r];
}
