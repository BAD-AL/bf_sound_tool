import 'dart:io';
import 'dart:typed_data';
import 'package:bf_sound_tool/bf_sound_tool.dart';
import 'package:bf_sound_tool/src/bf_sound_file_io.dart';

const _usage = '''
Usage: replace_sounds -i <input.lvl> -r <folder> [options]

Replaces sounds in an Xbox, PC, PS2, or PSP .lvl file using WAV files from a folder.

AUTOMATIC CONVERSION:
  - Multi-channel WAVs are mixed to mono for sample entries.
  - Stereo is preserved for stereo stream entries.
  - Automatic encoding to VAG (PSP/PS2) or Xbox ADPCM (Xbox/PC).
  - Supported formats: PCM16, PCM24, PCM32 int, 32-bit float.

PSP STREAMS:
  - Supply a WAV produced by at3tool (ATRAC3plus). 
  - These are passed through as-is without re-encoding.

SAMPLE RATES:
  - By default, WAVs are resampled to match the ORIGINAL entry's rate.
  - Override for all files with --rate <hz>.
  - Override for specific files using a 'rates.txt' sidecar in the folder.

rates.txt format:
  sound_name: 22050
  # comment lines are supported
  other_sound: 11025

Options:
  -i <file>       Input .lvl file  [required]
  -r <folder>     Folder containing replacement .wav files  [required]
  -p xbox|ps2|pc|psp  Source platform  [default: pc]
  -v bf1|bf2      Game version  [default: bf2]
  -o <file>       Output .lvl file  [default: <input>_replaced.lvl]
  --rate <hz>     Override sample rate for ALL replacements
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
  String version = 'bf2';
  String? outputFile;
  int? globalRate;
  bool logOnly = false;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '-i': inputFile = args[++i];
      case '-r': replacementFolder = args[++i];
      case '-p': platform = args[++i].toLowerCase();
      case '-v': version = args[++i].toLowerCase();
      case '-o': outputFile = args[++i];
      case '--rate': globalRate = int.parse(args[++i]);
      case '--log-only': logOnly = true;
    }
  }

  if (inputFile == null || replacementFolder == null) {
    stderr.writeln('Error: -i and -r are required.');
    exitCode = 1; return;
  }

  final folder = Directory(replacementFolder);
  outputFile ??= '${inputFile.substring(0, inputFile.lastIndexOf('.'))}_replaced.lvl';

  // ── Load sidecar rates ─────────────────────────────────────────────────────
  final sidecarRates = _loadSidecar(replacementFolder);

  // ── Parse LVL and map files ───────────────────────────────────────────────
  stdout.writeln('Parsing $inputFile as $platform ($version)...');
  final sf = BattlefrontSoundFile(File(inputFile).readAsBytesSync(), platform, version);
  final mappings = sf.mapWavsInFolder(folder);

  if (mappings.isEmpty) {
    stderr.writeln('No matching .wav files found in $replacementFolder');
    return;
  }

  // ── Print plan ────────────────────────────────────────────────────────────
  stdout.writeln('\nReplacement plan:');
  stdout.writeln('${'Name'.padRight(44)}${'DstRate'.padRight(10)}Status');
  stdout.writeln('-' * 60);

  final replacements = <SoundRecord, Uint8List>{};
  final rateOverrides = <SoundRecord, int>{};

  for (final entry in mappings.entries) {
    final record = entry.key;
    final file = entry.value;
    final targetRate = sidecarRates[record.name] ?? globalRate;
    
    stdout.writeln('${record.name.padRight(44)}'
        '${(targetRate ?? "native").toString().padRight(10)}OK');
    
    replacements[record] = file.readAsBytesSync();
    if (targetRate != null) rateOverrides[record] = targetRate;
  }

  stdout.writeln('\nReplacing ${replacements.length} entries...');
  if (logOnly) return;

  final outBytes = sf.replaceManyWithWav(replacements, newSampleRates: rateOverrides);
  File(outputFile).writeAsBytesSync(outBytes);
  stdout.writeln('Done. Written: $outputFile (${outBytes.length} bytes)');
}

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
