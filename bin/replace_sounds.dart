import 'dart:io';
import 'dart:typed_data';
import 'package:sound_ripper/sound_ripper.dart';

const _usage = '''
Usage: replace_sounds -i <input.lvl> -r <folder> [options]

Replaces sounds in an Xbox, PC, PS2, or PSP .lvl file using WAV files from a folder.

WAV files must be named <soundname>.wav (matching the sound entry name exactly).
Aliases are skipped automatically.
Multi-channel WAV files are mixed to mono for sample (non-stream) entries.
Stereo WAV files are kept stereo when replacing stereo stream entries.
Supported input formats: PCM16, PCM24, PCM32 int, 32-bit float.

PSP streams: supply a WAV produced by at3tool. The file is passed through as-is.

Sample rate: by default each replacement is kept at the WAV file's native rate.
Override globally with --rate, or per-entry in rates.txt (sidecar in the folder).

rates.txt format (one entry per line, lines starting with # are comments):
  soundname: 22050
  other_sound: 11025

Options:
  -i <file>       Input .lvl file  [required]
  -r <folder>     Folder containing replacement .wav files  [required]
  -p xbox|ps2|pc|psp  Source platform  [default: pc]
  -v bf1|bf2      Game version  [default: bf2]
  -o <file>       Output .lvl file  [default: <input>_replaced.lvl]
  --rate <hz>     Override sample rate for all replacements
  --log-only      Show replacement plan without writing files
  -h, --help      Show this help
''';

void main(List<String> args) {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stdout.write(_usage);
    return;
  }

  String? inputFile;
  String? replacementFolder;
  String platform = 'pc';
  String version  = 'bf2';
  String? outputFile;
  int? globalRate;
  bool logOnly = false;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '-i':         inputFile          = args[++i];
      case '-r':         replacementFolder  = args[++i];
      case '-p':         platform           = args[++i].toLowerCase();
      case '-v':         version            = args[++i].toLowerCase();
      case '-o':         outputFile         = args[++i];
      case '--rate':     globalRate         = int.parse(args[++i]);
      case '--log-only': logOnly            = true;
    }
  }

  if (inputFile == null) {
    stderr.writeln('Error: -i <file> is required.');
    exitCode = 1; return;
  }
  if (replacementFolder == null) {
    stderr.writeln('Error: -r <folder> is required.');
    exitCode = 1; return;
  }
  if (!['xbox', 'ps2', 'psp', 'pc'].contains(platform)) {
    stderr.writeln('Error: unsupported platform "$platform" (use xbox, ps2, psp, pc)');
    exitCode = 1; return;
  }

  final lvlFile = File(inputFile);
  if (!lvlFile.existsSync()) {
    stderr.writeln('Error: file not found: $inputFile'); exitCode = 1; return;
  }
  final folder = Directory(replacementFolder);
  if (!folder.existsSync()) {
    stderr.writeln('Error: folder not found: $replacementFolder'); exitCode = 1; return;
  }

  outputFile ??= '${inputFile.substring(0, inputFile.lastIndexOf('.'))}_replaced.lvl';

  // ── Load sidecar rates ─────────────────────────────────────────────────────

  final sidecarRates = _loadSidecar(replacementFolder);
  if (sidecarRates.isNotEmpty) {
    stdout.writeln('Loaded ${sidecarRates.length} rate override(s) from rates.txt');
  }

  // ── Parse LVL ─────────────────────────────────────────────────────────────

  stdout.writeln('Parsing $inputFile as $platform ($version)...');
  final origBytes = lvlFile.readAsBytesSync();
  final sf        = BattlefrontSoundFile(origBytes, platform, version);

  final allSounds = sf.getAllSounds();
  stdout.writeln('  ${allSounds.length} entries (${allSounds.where((r) => !r.skip).length} active, '
      '${allSounds.where((r) => r.skip).length} aliases)');

  // Build name → record map (active entries only).
  final recordMap = <String, SoundRecord>{};
  for (final r in allSounds) {
    if (!r.skip) recordMap[r.name] = r;
  }

  // ── Scan WAV files ─────────────────────────────────────────────────────────

  final wavFiles = folder
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.wav'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (wavFiles.isEmpty) {
    stderr.writeln('No .wav files found in $replacementFolder');
    exitCode = 1; return;
  }

  // ── Build replacement plan ─────────────────────────────────────────────────

  stdout.writeln('\nReplacement plan:');
  stdout.writeln('${'Name'.padRight(44)}${'SrcRate'.padRight(10)}${'DstRate'.padRight(10)}Status');
  stdout.writeln('-' * 74);

  final plan = <_Entry>[];
  int skippedAlias = 0, skippedUnknown = 0;

  for (final wavFile in wavFiles) {
    final baseName = _baseName(wavFile.path);
    final record   = recordMap[baseName];

    if (record == null) {
      // Check if it's an alias (skip=true entry with this name).
      final alias = allSounds.where((r) => r.name == baseName && r.skip).firstOrNull;
      if (alias != null) {
        stdout.writeln('${baseName.padRight(44)}${''.padRight(10)}${''.padRight(10)}'
            'SKIP (alias — no audio data stored in this file)');
        skippedAlias++;
      } else {
        stdout.writeln('${baseName.padRight(44)}${''.padRight(10)}${''.padRight(10)}'
            'SKIP (not found in lvl)');
        skippedUnknown++;
      }
      continue;
    }

    // Determine target sample rate.
    final targetRate = sidecarRates[baseName] ?? globalRate;
    // null → keep WAV's native rate (determined after parsing)

    plan.add(_Entry(wavFile, record, targetRate));
  }

  if (plan.isEmpty) {
    stderr.writeln('\nNo matching entries found — nothing to replace.');
    exitCode = 1; return;
  }

  // Print planned entries (need to peek at WAV rates for display).
  for (final e in plan) {
    final wavBytes = e.wavFile.readAsBytesSync();
    e.wavCache = wavBytes;

    // PSP streams: passthrough of at3plus WAV — read header only, no PCM decode.
    if (e.record.isStream && platform == 'psp') {
      final info = WavParser.readInfo(wavBytes);
      if (info == null) {
        stdout.writeln('${e.record.name.padRight(44)}${'?'.padRight(10)}${'?'.padRight(10)}'
            'ERROR: not a valid RIFF/WAV file');
        continue;
      }
      e.nativeRate = info.sampleRate;
      final dst = e.targetRate ?? info.sampleRate;
      stdout.writeln('${e.record.name.padRight(44)}'
          '${info.sampleRate.toString().padRight(10)}'
          '${dst.toString().padRight(10)}'
          'OK (at3plus passthrough)');
      continue;
    }

    WavParser wav;
    try {
      wav = WavParser.parse(wavBytes);
    } catch (ex) {
      stdout.writeln('${e.record.name.padRight(44)}${'?'.padRight(10)}${'?'.padRight(10)}'
          'ERROR: $ex');
      continue;
    }
    e.nativeRate = wav.sampleRate;
    final dst    = e.targetRate ?? wav.sampleRate;
    final resamp = dst != wav.sampleRate ? ' (resample)' : '';
    final stereoNote = e.record.isStream && e.record.channels == 2 && wav.channels >= 2
        ? ' stereo' : '';
    stdout.writeln('${e.record.name.padRight(44)}'
        '${wav.sampleRate.toString().padRight(10)}'
        '${dst.toString().padRight(10)}'
        'OK$resamp$stereoNote');
  }

  if (skippedAlias > 0 || skippedUnknown > 0) {
    stdout.writeln('\n  Skipped: $skippedAlias alias(es), $skippedUnknown unknown name(s)');
  }
  stdout.writeln('  Replacing: ${plan.length} entries');

  if (logOnly) return;

  // ── Encode and collect replacements ───────────────────────────────────────

  stdout.writeln('\nEncoding...');
  final batchMap = <SoundRecord, Uint8List>{};

  for (int idx = 0; idx < plan.length; idx++) {
    final e = plan[idx];
    stdout.write('\r  [${idx + 1}/${plan.length}] ${e.record.name.padRight(44)}');

    final wavBytes = e.wavCache ?? e.wavFile.readAsBytesSync();

    // PSP streams: raw at3plus WAV bytes passed through as-is.
    if (e.record.isStream && platform == 'psp') {
      e.resolvedRate = e.targetRate ?? e.nativeRate;
      batchMap[e.record] = wavBytes;
      continue;
    }

    WavParser wav;
    try {
      wav = WavParser.parse(wavBytes);
    } catch (ex) {
      stdout.writeln('');
      stderr.writeln('Error reading ${e.wavFile.path}: $ex — skipping.');
      continue;
    }

    final targetRate = e.targetRate ?? wav.sampleRate;
    e.resolvedRate = targetRate;

    if (e.record.isStream) {
      batchMap[e.record] = _encodeStream(wav, e.record, platform, targetRate);
    } else {
      final pcm = PcmResampler.resample(wav.samples, wav.sampleRate, targetRate);
      batchMap[e.record] = _encodeSample(pcm, platform);
    }
  }
  stdout.writeln('\r  Done.${' ' * 60}');

  // replaceAudioBatch takes a single newSampleRate for all entries.
  // If rates differ per entry, fall back to per-entry replacement.
  final rates = plan.map((e) => e.resolvedRate).whereType<int>().toSet();
  final Uint8List outBytes;
  if (rates.length <= 1) {
    outBytes = sf.replaceAudioBatch(batchMap, newSampleRate: rates.firstOrNull);
  } else {
    outBytes = _replaceWithMixedRates(origBytes, platform, version, batchMap, plan);
  }

  File(outputFile).writeAsBytesSync(outBytes);
  stdout.writeln('Done. Written: $outputFile  '
      '(${origBytes.length} → ${outBytes.length} bytes)');
}

// ── Per-entry replacement when rates differ ────────────────────────────────

/// Falls back to chaining individual replacements when entries target
/// different sample rates. This is rare in practice (most sessions either
/// keep the original rate or apply one global --rate).
Uint8List _replaceWithMixedRates(
  Uint8List origBytes,
  String platform,
  String version,
  Map<SoundRecord, Uint8List> batchMap,
  List<_Entry> plan,
) {
  // Group by rate and do one batch per rate group.
  final byRate = <int, Map<SoundRecord, Uint8List>>{};
  for (final e in plan) {
    if (e.resolvedRate == null) continue;
    final audio = batchMap[e.record];
    if (audio == null) continue;
    byRate.putIfAbsent(e.resolvedRate!, () => {})[e.record] = audio;
  }

  // Re-parse after each rate group so offsets stay valid for the next pass.
  Uint8List current = origBytes;
  for (final rate in byRate.keys) {
    final tempSf = BattlefrontSoundFile(current, platform, version);
    final remapped = <SoundRecord, Uint8List>{};
    for (final entry in byRate[rate]!.entries) {
      final fresh = tempSf.getSound(entry.key.name);
      if (fresh != null) remapped[fresh] = entry.value;
    }
    current = tempSf.replaceAudioBatch(remapped, newSampleRate: rate);
  }
  return current;
}

// ── Stream encoding ────────────────────────────────────────────────────────

/// Encodes a PCM WAV to the correct stream format for [platform].
///
/// PSP streams never reach this path — they are handled as raw passthrough
/// before WavParser is called.
///
/// Preserves stereo when [record.channels] == 2 and the WAV has ≥ 2 channels.
/// Mono WAVs replacing a stereo stream have their single channel duplicated.
Uint8List _encodeStream(
    WavParser wav, SoundRecord record, String platform, int targetRate) {
  final outChannels = record.channels;

  if (platform == 'ps2') {
    if (outChannels == 2) {
      final (left, right) = _stereoChannels(wav, targetRate);
      return VagEncoder.encodeStereoPs2(left, right, record.substreamInterleave);
    } else {
      final pcm = PcmResampler.resample(wav.samples, wav.sampleRate, targetRate);
      return VagEncoder.encode(pcm);
    }
  }

  // Xbox and PC streams → Xbox ADPCM (mono or stereo).
  if (outChannels == 2) {
    final (left, right) = _stereoChannels(wav, targetRate);
    return XboxAdpcmEncoder.encodeStereo(left, right);
  } else {
    final pcm = PcmResampler.resample(wav.samples, wav.sampleRate, targetRate);
    return XboxAdpcmEncoder.encode(pcm);
  }
}

/// Returns resampled (left, right) channels from [wav].
/// If [wav] is mono, both channels are the same buffer (no duplication needed
/// since XboxAdpcmEncoder.encodeStereo reads each independently).
(Int16List, Int16List) _stereoChannels(WavParser wav, int targetRate) {
  final left  = PcmResampler.resample(
      wav.channelSamples[0], wav.sampleRate, targetRate);
  final right = wav.channels >= 2
      ? PcmResampler.resample(wav.channelSamples[1], wav.sampleRate, targetRate)
      : left; // mono → duplicate channel
  return (left, right);
}

// ── Sample encoding helpers ────────────────────────────────────────────────

Uint8List _encodeSample(Int16List pcm, String platform) => switch (platform) {
      'ps2' || 'psp' => VagEncoder.encode(pcm),
      'xbox'         => XboxAdpcmEncoder.encode(pcm),
      _              => _pcm16Bytes(pcm),  // PC: raw PCM16
    };

Uint8List _pcm16Bytes(Int16List samples) {
  final out = Uint8List(samples.length * 2);
  final bd  = ByteData.view(out.buffer);
  for (int i = 0; i < samples.length; i++) {
    bd.setInt16(i * 2, samples[i], Endian.little);
  }
  return out;
}

// ── Sidecar loader ─────────────────────────────────────────────────────────

Map<String, int> _loadSidecar(String folderPath) {
  final file = File('$folderPath/rates.txt');
  if (!file.existsSync()) return {};
  final rates = <String, int>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final colon = trimmed.indexOf(':');
    if (colon < 1) continue;
    final name = trimmed.substring(0, colon).trim();
    final rate = int.tryParse(trimmed.substring(colon + 1).trim());
    if (name.isNotEmpty && rate != null) rates[name] = rate;
  }
  return rates;
}

// ── Utilities ──────────────────────────────────────────────────────────────

String _baseName(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot  = name.lastIndexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}

// ── Plan entry ────────────────────────────────────────────────────────────

class _Entry {
  final File wavFile;
  final SoundRecord record;
  final int? targetRate;   // from sidecar or --rate; null = use WAV native
  Uint8List? wavCache;
  int? nativeRate;
  int? resolvedRate;

  _Entry(this.wavFile, this.record, this.targetRate);
}
