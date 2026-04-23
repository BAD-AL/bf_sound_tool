import 'dart:typed_data';
import 'amb_deinterlacer.dart';
import 'bank_parser.dart';
import 'dictionary.dart';
import 'sound_record.dart';
import 'sound_replacer.dart';
import 'sound_replacer_ext.dart';
import 'ucf_chunk.dart';
import 'ucf_parser.dart';
import 'vag_decoder.dart';
import 'wav_writer.dart';
import 'xbox_adpcm_decoder.dart';

/// High-level API for a Battlefront sound `.lvl` / `.bnk` / `.str` file.
///
/// Parses the file on construction and exposes [SoundRecord] metadata.
/// Holds the source bytes internally for on-demand audio extraction.
///
/// Usage:
/// ```dart
/// final sf = BattlefrontSoundFile(bytes, 'xbox', 'bf2', dictionary: dict);
/// final record = sf.getSound('hot_amb_wind');
/// final wav = sf.extractWav(record!);
/// // — or, if you know the name is present —
/// final wav = sf.extractWavByName('hot_amb_wind');
/// ```
class BattlefrontSoundFile {
  final String platform;
  final String version;
  final Uint8List _bytes;
  final UcfChunk _root;
  final List<SoundBank> _banks;
  final List<SoundRecord> _records;

  /// Parse [bytes] as a Battlefront sound file for [platform] and [version].
  ///
  /// The built-in BF1/BF2 dictionary (33 000+ entries) is always loaded.
  /// Supply [extraDictionary] as a multi-line string to add project-specific
  /// or modded sound names on top of the built-in set.
  BattlefrontSoundFile(
    Uint8List bytes,
    this.platform,
    this.version, {
    String? extraDictionary,
  })  : _bytes = bytes,
        _root = UcfParser.parse(bytes),
        _banks = [],
        _records = [] {
    final dict = _buildDict(extraDictionary);
    _banks.addAll(BankParser.parseBanks(_root, _bytes, dict, platform: platform));
    _records.addAll(_buildRecordsFromBanks(_banks));
  }

  // ── Construction ──────────────────────────────────────────────────────────

  static Dictionary _buildDict(String? extraDictionary) {
    final dict = Dictionary()..loadBuiltin();
    if (extraDictionary != null) dict.loadString(extraDictionary);
    return dict;
  }

  static List<SoundRecord> _buildRecordsFromBanks(List<SoundBank> banks) {
    final records = <SoundRecord>[];
    for (int b = 0; b < banks.length; b++) {
      final bank = banks[b];
      // Sample banks are always mono (PSP/PS2 sample channel field unreliable).
      final wavChannels = bank.isStream ? bank.channels : 1;
      for (final entry in bank.entries) {
        records.add(SoundRecord(
          name: entry.name,
          nameHash: entry.nameHash,
          sampleRate: entry.sampleRate,
          channels: wavChannels,
          isStream: bank.isStream,
          skip: entry.skip,
          aliasFor: entry.aliasFor,
          dataSize: entry.dataSize,
          audioOffset: entry.audioOffset,
          audioReadSize: entry.audioReadSize,
          bankIndex: b,
          substreamInterleave: bank.substreamInterleave,
          bankFormat: bank.format,
        ));
      }
    }
    return records;
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  /// All records, including those flagged [SoundRecord.skip].
  List<SoundRecord> getAllSounds() => List.unmodifiable(_records);

  /// Only records where [SoundRecord.skip] is false.
  List<SoundRecord> getActiveSounds() =>
      List.unmodifiable(_records.where((r) => !r.skip));

  /// Returns the first record whose [SoundRecord.name] matches [name],
  /// or `null` if not found.
  SoundRecord? getSound(String name) {
    for (final r in _records) {
      if (r.name == name) return r;
    }
    return null;
  }

  // ── Extraction by record ──────────────────────────────────────────────────

  /// Raw audio bytes for [record] (no WAV header).
  Uint8List extractRawAudio(SoundRecord record) => Uint8List.sublistView(
        _bytes,
        record.audioOffset,
        record.audioOffset + record.audioReadSize,
      );

  /// WAV-wrapped audio for [record].
  ///
  /// Stream banks (Xbox and PC) → Xbox/IMA ADPCM (format 0x0069).
  /// Sample banks (PC, non-stream) → PCM16 (format 0x0001).
  /// Xbox sample banks → Xbox ADPCM (0x0069) OR PCM16 (0x0001) depending on format.
  ///
  /// PS2 VAG is decoded to PCM16 WAV.
  ///
  /// For PS2 stereo ambient streams that require deinterleaving into
  /// separate front/back PCM files, use [extractAmbWavs] instead.
  Uint8List extractWav(SoundRecord record) {
    final audio = extractRawAudio(record);

    // PSP streams: audio is already a complete RIFF/WAV file (WAVE_FORMAT_EXTENSIBLE,
    // ATRAC3plus subformat). Return bytes as-is — no header construction needed.
    if (platform == 'psp' && record.isStream) {
      return audio;
    }

    // PSP samples: raw VAG ADPCM blocks, always mono (same decoder as PS2).
    if (platform == 'psp') {
      final pcm = VagDecoder.decode(audio, 1, 0);
      return WavWriter.buildPcm16(pcm, record.sampleRate, 1);
    }

    if (platform == 'ps2') {
      // Decode PS2 VAG ADPCM → PCM16 WAV.
      // Stereo streams deinterleave channels using the bank's substreamInterleave.
      final pcm = VagDecoder.decode(
        audio,
        record.channels,
        record.substreamInterleave,
      );
      return WavWriter.buildPcm16(pcm, record.sampleRate, record.channels);
    }

    // Xbox / PC logic:
    // 1. Streams are always Xbox ADPCM.
    // 2. PC Samples (e.g. common.bnk) are always PCM16.
    // 3. Xbox Samples are usually ADPCM, but can be PCM16 if bank format is 2.
    bool encodedAsAdpcm = false;
    if (record.isStream) {
      encodedAsAdpcm = true;
    } else if (platform == 'xbox') {
      // Bank format 2 on Xbox indicates PCM16 (e.g. ARE.lvl Bank 2).
      // Bank format 4/5 indicates ADPCM (e.g. hot.lvl Bank 2).
      encodedAsAdpcm = record.bankFormat != 2;
    } else if (platform == 'pc') {
      // PC sample banks are always PCM16.
      encodedAsAdpcm = false;
    }

    if (encodedAsAdpcm) {
      final pcm = XboxAdpcmDecoder.decode(audio, record.channels);
      return WavWriter.buildPcm16(pcm, record.sampleRate, record.channels);
    } else {
      return WavWriter.buildPcm16(audio, record.sampleRate, record.channels);
    }
  }

  /// Deinterleaves a PS2 stereo ambient stream into separate front and back WAVs.
  ///
  /// PS2 `_amb_` entries interleave two stereo PCM16 substreams at
  /// [AmbDeinterlacer.interlaceSampleCount]-sample boundaries.
  ///
  /// Throws [ArgumentError] if [record] is not a stereo stream, or if
  /// [platform] is not `'ps2'` (PC streams are ADPCM-encoded and use a
  /// different block-level interleave — use [extractWav] for those).
  (Uint8List front, Uint8List back) extractAmbWavs(SoundRecord record) {
    if (!record.isStream || record.channels != 2) {
      throw ArgumentError(
        '${record.name} is not a stereo stream and cannot be deinterleaved',
      );
    }
    if (platform != 'ps2') {
      throw ArgumentError(
        'extractAmbWavs is only valid for PS2 streams. '
        'PC streams are ADPCM-encoded — use extractWav instead.',
      );
    }
    final audio = extractRawAudio(record);
    final (fnt, bck) = AmbDeinterlacer.deinterlace(audio);
    return (
      WavWriter.buildPcm16(fnt, record.sampleRate, 2),
      WavWriter.buildPcm16(bck, record.sampleRate, 2),
    );
  }

  // ── Replacement ──────────────────────────────────────────────────────────

  /// Replace the audio for [record] with [newAudio] and return new file bytes.
  ///
  /// [newAudio] must be in the raw format [extractRawAudio] returns for this
  /// platform: PSP streams → complete RIFF/WAV (ATRAC3+); PSP/PS2 samples →
  /// raw VAG blocks; Xbox → raw Xbox ADPCM blocks; PC samples → raw PCM16
  /// bytes; PC streams → raw Xbox ADPCM blocks. No WAV headers in any case.
  ///
  /// All UCF structure, metadata, and non-audio chunks are preserved.
  /// Only the target entry's audio data and affected size fields are updated.
  Uint8List replaceAudio(SoundRecord record, Uint8List newAudio,
          {int? newSampleRate}) =>
      SoundReplacer.replace(_bytes, _root, _banks, record, newAudio, platform,
          newSampleRate: newSampleRate);

  /// Replace the audio for the entry named [name] and return new file bytes.
  /// Throws [ArgumentError] if [name] is not found.
  Uint8List replaceAudioByName(String name, Uint8List newAudio,
          {int? newSampleRate}) =>
      replaceAudio(_require(name), newAudio, newSampleRate: newSampleRate);

  /// Replace audio for multiple records in a single serialization pass.
  /// All entries are replaced simultaneously — no chained re-parses needed.
  /// 
  /// [replacements] maps each SoundRecord to its new raw audio bytes.
  /// [newSampleRates] optionally overrides the playback frequency for specific entries.
  Uint8List replaceAudioBatch(Map<SoundRecord, Uint8List> replacements,
          {Map<SoundRecord, int>? newSampleRates}) =>
      SoundReplacer.replaceMany(_bytes, _root, _banks, replacements, platform,
          newSampleRates: newSampleRates);

  /// Replace the audio for [record] with a standard WAV file.
  ///
  /// Automatically handles resampling and platform-specific encoding
  /// (Xbox ADPCM, VAG, etc.).
  Uint8List replaceWithWav(SoundRecord record, Uint8List wavBytes,
      {int? newSampleRate}) {
    final rawAudio = SoundReplacerExt.convertWav(wavBytes, record, platform,
        targetSampleRate: newSampleRate);
    return replaceAudio(record, rawAudio, newSampleRate: newSampleRate);
  }

  /// Replace audio for multiple records using standard WAV files.
  /// 
  /// [replacements] maps each SoundRecord to its new standard WAV bytes.
  /// [newSampleRates] optionally overrides the playback frequency for specific entries.
  Uint8List replaceManyWithWav(Map<SoundRecord, Uint8List> replacements,
      {Map<SoundRecord, int>? newSampleRates}) {
    final rawReplacements = <SoundRecord, Uint8List>{};
    for (final entry in replacements.entries) {
      final overrideRate = newSampleRates?[entry.key];
      rawReplacements[entry.key] = SoundReplacerExt.convertWav(
          entry.value, entry.key, platform,
          targetSampleRate: overrideRate);
    }
    return replaceAudioBatch(rawReplacements, newSampleRates: newSampleRates);
  }

  // ── By-name convenience overloads ─────────────────────────────────────────
  //
  // These perform an O(n) name scan on each call.
  // Use getSound() + cache the SoundRecord when extracting the same
  // entry multiple times.

  /// Raw audio bytes for the entry named [name].
  /// Throws [ArgumentError] if [name] is not found.
  Uint8List extractRawAudioByName(String name) =>
      extractRawAudio(_require(name));

  /// WAV bytes for the entry named [name].
  /// Throws [ArgumentError] if [name] is not found.
  Uint8List extractWavByName(String name) => extractWav(_require(name));

  /// Deinterleaved front + back WAVs for the ambient entry named [name].
  /// Throws [ArgumentError] if [name] is not found or is not a stereo stream.
  (Uint8List front, Uint8List back) extractAmbWavsByName(String name) =>
      extractAmbWavs(_require(name));

  // ── Internal ──────────────────────────────────────────────────────────────

  SoundRecord _require(String name) {
    final r = getSound(name);
    if (r == null) {
      throw ArgumentError.value(name, 'name', 'sound not found in this file');
    }
    return r;
  }
}
