import 'dart:io';
import 'dart:typed_data';
import 'package:bf_sound_tool/bf_sound_tool.dart';

const _usage = '''
Usage: bf_sound_tool -i <file.lvl> [options]

Options:
  -i <file>         Input .lvl (or .str / .bnk) file  [required]
  -p xbox|ps2|pc|psp  Platform  [default: xbox]
  -v bf1|bf2        Game version  [default: bf2]
  -d <dir>          Output directory  [default: <file>_out/]
  -t <name>         Extract only the named sound entry
  -o <file>         Output .lvl path (used with --replace)
  --list            Print all sound entries without extracting
  --verify          Check structural integrity (sequential layout, size totals)
  --extract         Extract all sounds to output directory  [default action]
  --log-only        Log extraction plan without writing WAV files
  --replace <name>  Replace a named entry's audio (requires --with and -o)
  --with <file>     Replacement audio file (WAV auto-converted for PSP samples)
  --rate <hz>       Override target sample rate for replacement conversion
                    (default: match original entry; PSP common: 11025, 6004, 5004)
  --dict <file>     Path to dictionary.txt  [auto-detected if omitted]
  -h, --help        Show this help
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stdout.write(_usage);
    return;
  }
  
  // --- parse args ---
  String? inputFile;
  String platform = 'xbox';
  String version = 'bf2';
  String? outputDir;
  String? outputFile;
  String? dictPath;
  String? targetName;
  String? replaceName;
  String? replaceWith;
  int? overrideRate;
  bool listMode = false;
  bool verifyMode = false;
  bool logOnly = false;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '-i':
        inputFile = args[++i];
      case '-p':
        platform = args[++i].toLowerCase();
      case '-v':
        version = args[++i].toLowerCase();
      case '-d':
        outputDir = args[++i];
      case '-o':
        outputFile = args[++i];
      case '-t':
        targetName = args[++i];
      case '--replace':
        replaceName = args[++i];
      case '--with':
        replaceWith = args[++i];
      case '--rate':
        overrideRate = int.parse(args[++i]);
      case '--dict':
        dictPath = args[++i];
      case '--list':
        listMode = true;
      case '--verify':
        verifyMode = true;
      case '--log-only':
        logOnly = true;
      case '--extract':
        break; // default action, no-op
    }
  }

  if (inputFile == null) {
    stderr.writeln('Error: -i <file> is required.');
    stderr.write(_usage);
    exitCode = 1;
    return;
  }

  final file = File(inputFile);
  if (!file.existsSync()) {
    stderr.writeln('Error: file not found: $inputFile');
    exitCode = 1;
    return;
  }

  if (!['xbox', 'ps2', 'pc', 'psp'].contains(platform)) {
    stderr.writeln('Error: invalid platform "$platform" (use xbox, ps2, pc, psp)');
    exitCode = 1;
    return;
  }

  // --- load extra dictionary (--dict flag), if provided ---
  String? extraDictionary;
  if (dictPath != null) {
    final dictFile = File(dictPath);
    if (!dictFile.existsSync()) {
      stderr.writeln('Warning: dictionary file not found: $dictPath');
    } else {
      extraDictionary = dictFile.readAsStringSync();
    }
  }

  // --- parse (built-in dictionary always loaded automatically) ---
  stdout.writeln('Parsing $inputFile for $platform ($version)...');
  final sf = BattlefrontSoundFile(
    file.readAsBytesSync(),
    platform,
    version,
    extraDictionary: extraDictionary,
  );

  final allSounds = sf.getAllSounds();
  if (allSounds.isEmpty) {
    stderr.writeln('No sound banks found in $inputFile');
    exitCode = 1;
    return;
  }

  // Print bank summary (group by bankIndex).
  final bankCount = allSounds.map((r) => r.bankIndex).toSet().length;
  stdout.writeln('Found $bankCount bank(s):');
  for (int b = 0; b < bankCount; b++) {
    final inBank = allSounds.where((r) => r.bankIndex == b).toList();
    final first = inBank.first;
    stdout.writeln('  Bank ${b + 1}: ${inBank.length}'
        ' ${first.typeLabel} entries');
  }

  if (listMode) {
    _printList(allSounds);
    //_printListCsv(allSounds);
    //_printSfx(allSounds);
    return;
  }

  if (verifyMode) {
    _verify(file.readAsBytesSync(), platform, allSounds);
    return;
  }

  // --- replace ---
  if (replaceName != null) {
    if (replaceWith == null) {
      stderr.writeln('Error: --replace requires --with <file>');
      exitCode = 1;
      return;
    }
    if (outputFile == null) {
      stderr.writeln('Error: --replace requires -o <output.lvl>');
      exitCode = 1;
      return;
    }
    final withFile = File(replaceWith);
    if (!withFile.existsSync()) {
      stderr.writeln('Error: replacement file not found: $replaceWith');
      exitCode = 1;
      return;
    }
    final record = sf.getSound(replaceName);
    if (record == null) {
      stderr.writeln('Error: no entry named "$replaceName" found.');
      exitCode = 1;
      return;
    }
    stdout.writeln('Replacing "$replaceName" with $replaceWith...');
    stdout.writeln('  Original: ${record.dataSize} bytes'
        '  offset=${record.formattedOffset}');
    
    final withBytes = withFile.readAsBytesSync();
    final newBytes = replaceWith.toLowerCase().endsWith('.wav')
        ? sf.replaceWithWav(record, withBytes, newSampleRate: overrideRate)
        : sf.replaceAudio(record, withBytes, newSampleRate: overrideRate);
        
    File(outputFile).writeAsBytesSync(newBytes);
    stdout.writeln('  Written: $outputFile (${newBytes.length} bytes)');
    return;
  }

  // --- extract ---
  outputDir ??= '${inputFile.substring(0, inputFile.lastIndexOf('.'))}_out';
  if (!logOnly) Directory(outputDir).createSync(recursive: true);

  final toExtract = targetName != null
      ? allSounds.where((r) => r.name == targetName).toList()
      : sf.getActiveSounds();

  if (targetName != null && toExtract.isEmpty) {
    stderr.writeln('Error: no entry named "$targetName" found.');
    exitCode = 1;
    return;
  }

  int extracted = 0;
  int skipped = 0;

  for (final record in toExtract) {
    if (record.skip) {
      stdout.writeln('  SKIP ${record.name}');
      skipped++;
      continue;
    }

    final outName = '$outputDir/${record.name}.wav';
    stdout.writeln('  ${record.name}'
        '  rate=${record.sampleRate}'
        '  size=${record.audioReadSize}'
        '  bank=${record.bankIndex + 1}'
        '  offset=${record.formattedOffset}');

    if (!logOnly) {
      if (platform == 'ps2' &&
          record.name.contains('_amb_') &&
          record.channels == 2) {
        final (fnt, bck) = sf.extractAmbWavs(record);
        final base = outName.substring(0, outName.length - 4);
        File('${base}_fnt.wav').writeAsBytesSync(fnt);
        File('${base}_bck.wav').writeAsBytesSync(bck);
        stdout.writeln('    → deinterlaced: ${base}_fnt.wav + ${base}_bck.wav');
      } else {
        File(outName).writeAsBytesSync(sf.extractWav(record));
      }
    }
    extracted++;
  }

  stdout.writeln(
    '\nDone. Extracted: $extracted  Skipped: $skipped'
    '${logOnly ? "  (log-only, no files written)" : "  → $outputDir/"}',
  );
}

void _verify(Uint8List bytes, String platform, List<SoundRecord> allSounds) {
  final dict  = Dictionary()..loadBuiltin();
  final root  = UcfParser.parse(bytes);
  final banks = BankParser.parseBanks(root, bytes, dict, platform: platform);

  int failures = 0;

  for (int b = 0; b < banks.length; b++) {
    final bank     = banks[b];
    final bankNum  = b + 1;
    final active   = bank.entries.where((e) => !e.skip).toList();
    final typeLabel = bank.isStream ? 'stream' : 'sample';

    stdout.writeln('Bank $bankNum ($typeLabel, ${bank.entries.length} entries, '
        '${active.length} active):');

    // Check 1: sequential audio layout.
    final chunkEnd = bank.dataChunk.bodyOffset + bank.dataChunk.size;
    int readPos = bank.dataChunk.bodyOffset;
    for (final e in bank.entries) {
      if (e.skip) continue;
      if (e.audioOffset != readPos) {
        stdout.writeln('  FAIL  ${e.name}: audioOffset=0x${e.audioOffset.toRadixString(16)}'
            ' expected=0x${readPos.toRadixString(16)}');
        failures++;
      }
      final entryEnd = e.audioOffset + e.dataSize;
      if (entryEnd > chunkEnd) {
        stdout.writeln('  FAIL  ${e.name}: data extends past chunk end'
            ' (entry ends at 0x${entryEnd.toRadixString(16)}'
            ', chunk ends at 0x${chunkEnd.toRadixString(16)}'
            ', overflow=${entryEnd - chunkEnd})');
        failures++;
      }
      readPos += e.dataSize + e.blockPadding;
    }

    // Check 2: data chunk is large enough to hold all active entry data.
    // (chunk size >= sum of entries; tail padding is normal and allowed)
    final sumData  = active.fold(0, (s, e) => s + e.dataSize);
    final sumPad   = active.fold(0, (s, e) => s + e.blockPadding);
    final sumSizes = sumData + sumPad;
    if (bank.dataChunk.size < sumSizes) {
      stdout.writeln('  FAIL  data chunk size=${bank.dataChunk.size}'
          ' is smaller than sum of entries=$sumSizes'
          ' (sumData=$sumData  sumPad=$sumPad'
          '  delta=${bank.dataChunk.size - sumSizes})');
      failures++;
    }

    // Check 3: no zero-size active entries.
    for (final e in active) {
      if (e.dataSize == 0) {
        stdout.writeln('  FAIL  ${e.name}: dataSize is 0');
        failures++;
      }
    }

    // Check 4: audio format validity per platform.
    for (final e in active) {
      final msg = _checkAudioFormat(bytes, e, platform, bank.isStream);
      if (msg != null) {
        stdout.writeln('  FAIL  ${e.name}: $msg');
        failures++;
      }
    }

    if (failures == 0) {
      final tail = bank.dataChunk.size - sumSizes;
      stdout.writeln('  OK    sequential layout ✓  chunk size ✓  '
          'no zero entries ✓  audio format ✓'
          '${tail > 0 ? "  (tail padding: $tail)" : ""}');
    }
  }

  stdout.writeln('');
  if (failures == 0) {
    stdout.writeln('PASS  ${banks.length} bank(s) verified, no issues found.');
  } else {
    stdout.writeln('FAIL  $failures issue(s) found.');
    exitCode = 1;
  }
}

/// Returns a failure description, or null if the audio looks valid for [platform].
String? _checkAudioFormat(
    Uint8List bytes, SoundEntry entry, String platform, bool isStream) {
  final offset = entry.audioOffset;
  final size   = entry.dataSize;
  if (size == 0) return null; // caught by check 3

  // ── PSP/PS2 sample banks: raw VAG ADPCM 16-byte blocks ───────────────────
  if ((platform == 'psp' || platform == 'ps2') && !isStream) {
    if (size % 16 != 0) {
      return 'VAG size $size not a multiple of 16';
    }
    // Spot-check first few and last block.
    bool hasEndFlag = false;
    for (int blk = 0; blk < size ~/ 16; blk++) {
      final base = offset + blk * 16;
      final predictorShift = bytes[base];
      final flags = bytes[base + 1];
      final predictor = (predictorShift >> 4) & 0xF;
      if (predictor > 4) {
        // Only check first 8 blocks and last block for speed.
        if (blk < 8 || blk == size ~/ 16 - 1) {
          return 'block $blk: predictor nibble $predictor out of range (0-4)';
        }
      }
      if (flags & 0x01 != 0) hasEndFlag = true;
    }
    if (!hasEndFlag) {
      return 'no end-of-data flag found in any VAG block';
    }
    return null;
  }

  // ── PSP stream banks: complete RIFF/WAV ──────────────────────────────────
  if (platform == 'psp' && isStream) {
    if (size < 12) return 'too small for RIFF header';
    if (bytes[offset]     != 0x52 || bytes[offset + 1] != 0x49 ||
        bytes[offset + 2] != 0x46 || bytes[offset + 3] != 0x46) {
      return 'missing RIFF header';
    }
    if (bytes[offset + 8]  != 0x57 || bytes[offset + 9]  != 0x41 ||
        bytes[offset + 10] != 0x56 || bytes[offset + 11] != 0x45) {
      return 'missing WAVE marker';
    }
    return null;
  }

  // ── Xbox/PC: raw IMA ADPCM blocks (no RIFF wrapper in the file).
  // Validate step index byte (offset+2 in each block) is in range 0-88.
  if (platform == 'xbox' || platform == 'pc') {
    if (!isStream && size >= 4) {
      final stepIndex = bytes[offset + 2];
      if (stepIndex > 88) {
        return 'IMA ADPCM block 0: step index $stepIndex out of range (0-88)';
      }
    }
    return null;
  }

  return null;
}

void _printList(List<SoundRecord> records) {
  stdout.writeln(
    '${'Bank'.padRight(5)}${'Name'.padRight(40)}'
    '${'Hash'.padRight(12)}${'Rate'.padRight(8)}'
    '${'Ch'.padRight(8)}${'Size'.padRight(12)}'
    '${'Skip'.padRight(6)}Offset',
  );
  stdout.writeln('-' * 109);
  for (final r in records) {
    final hash = '0x${r.nameHash.toRadixString(16).padLeft(8, '0')}';
    stdout.writeln(
      '${(r.bankIndex + 1).toString().padRight(5)}'
      '${r.name.padRight(40)}'
      '${hash.padRight(12)}'
      '${r.sampleRate.toString().padRight(8)}'
      '${r.channels.toString().padRight(8)}'
      '${r.audioReadSize.toString().padRight(12)}'
      '${(r.skip ? 'yes' : 'no').padRight(6)}'
      '${r.formattedOffset}',
    );
  }
}

void _printListCsv(List<SoundRecord> records) {
  print( "Bank,Name,Hash,Rate,Ch,size,isAlias?,Offset");
  for (final r in records) {
    final hash = '0x${r.nameHash.toRadixString(16)}';
    print( "${r.bankIndex+1},${r.name},$hash,${r.sampleRate},${r.channels},${r.audioReadSize},${r.skip},${r.formattedOffset}");
  }
}

void _printSfx(List<SoundRecord> records) {
  //print( "Bank,Name,Hash,Rate,Ch,size,isAlias?,Offset");
  print("//best-effort .sfx file");
  int bank = records[0].bankIndex;
  print("// soundbank: $bank");
  for (final r in records) {
    if(r.bankIndex != bank){
      bank = r.bankIndex;
      print("// end soundbank \n\n\n\n");
      print("// soundbank: $bank");
    }
    if(r.aliasFor != null){
      print("${r.name}.wav      -alias ps2 ${r.aliasFor}");  
    }else{
      print("${r.name}.wav      -resample ps2 ${r.sampleRate}");
    }
  }
}
