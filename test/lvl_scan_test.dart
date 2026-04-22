import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:bf_sound_tool/bf_sound_tool.dart';
import 'package:test/test.dart';

// ── Config ────────────────────────────────────────────────────────────────────

/// Directories to scan, keyed by (platform, version).
const _scanDirs = {
  ('xbox', 'bf2'): 'test/test_files/xbox',
  ('pc',   'bf2'): 'test/test_files/pc',
  ('ps2',  'bf2'): 'test/test_files/ps2',
  ('xbox', 'bf1'): 'test/test_files/BF1/xbox',
  ('pc',   'bf1'): 'test/test_files/BF1/pc',
  ('ps2',  'bf1'): 'test/test_files/BF1/ps2',
  ('psp',  'bf2'): 'test/test_files/psp',
};

/// true  → ffmpeg-check every 1-channel entry.
/// false → check only the first 15 and last 15 (faster, suitable for CI).
const bool testAll1ChannelSounds = false;

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<int> _ffmpegCheck(String wavPath) async {
  final outPath = '$wavPath.check.wav';
  final result = await Process.run('ffmpeg', [
    '-y', '-i', wavPath, '-f', 'wav', '-c:a', 'pcm_s16le', outPath,
  ]);
  if (File(outPath).existsSync()) File(outPath).deleteSync();
  return result.exitCode;
}

/// Write [wav] to [tmpDir]/[name].wav and run ffmpeg.
/// Returns an error string on failure, null on success.
Future<String?> _checkWav(Uint8List wav, String name, Directory tmpDir) async {
  final path = '${tmpDir.path}/$name.wav';
  File(path).writeAsBytesSync(wav);
  final code = await _ffmpegCheck(path);
  return code == 0 ? null : '$name | ffmpeg exit $code';
}

List<T> _firstAndLast15<T>(List<T> items) {
  if (items.length <= 30) return items;
  return [...items.take(15), ...items.skip(items.length - 15)];
}

// ── Per-file test suite ───────────────────────────────────────────────────────

void _registerLvlTests(String lvlPath, String platform, String version) {
  group(p.basename(lvlPath), () {
    late BattlefrontSoundFile sf;
    late Directory tmpDir;

    setUpAll(() async {
      final bytes = File(lvlPath).readAsBytesSync();
      sf = BattlefrontSoundFile(bytes, platform, version);
      tmpDir = Directory.systemTemp.createTempSync('bf_sound_tool_scan_');
    });

    tearDownAll(() => tmpDir.deleteSync(recursive: true));

    // ── Discovery ─────────────────────────────────────────────────────────────

    test('finds at least one sound', () {
      expect(sf.getAllSounds(), isNotEmpty);
    });

    // ── Listing ───────────────────────────────────────────────────────────────

    test('entry listing (informational)', () {
      final all = sf.getAllSounds();
      final bankCount = all.map((r) => r.bankIndex).toSet().length;
      for (int b = 0; b < bankCount; b++) {
        final inBank = all.where((r) => r.bankIndex == b).toList();
        final skipped = inBank.where((r) => r.skip).length;
        stdout.writeln('  Bank ${b + 1}: ${inBank.length - skipped} active'
            ' + $skipped skipped ${inBank.first.typeLabel} entries'
            ', ch=${inBank.first.channels}');
        for (final r in inBank) {
          final tag = r.skip ? ' [SKIP]' : '';
          stdout.writeln('    ${r.name.padRight(42)}'
              ' rate=${r.sampleRate.toString().padLeft(6)}'
              '  size=${r.dataSize.toString().padLeft(9)}'
              '  offset=${r.formattedOffset}'
              '$tag');
        }
      }
    });

    // ── 2-channel (stereo stream) ffmpeg validation ────────────────────────────

    test('2-channel stream entries: no ffmpeg errors', () async {
      final entries = sf
          .getActiveSounds()
          .where((r) => r.isStream && r.channels == 2)
          .toList();

      if (entries.isEmpty) {
        stdout.writeln('  (no active 2-channel stream entries)');
        return;
      }

      stdout.writeln('  Checking ${entries.length} 2-channel entries...');
      final failures = <String>[];
      for (final r in entries) {
        final err = await _checkWav(sf.extractWav(r), r.name, tmpDir);
        if (err != null) failures.add(err);
      }
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    }, timeout: const Timeout(Duration(minutes: 10)));

    // ── 1-channel (mono / sample bank) ffmpeg validation ──────────────────────

    test(
      '1-channel entries: no ffmpeg errors'
      '${testAll1ChannelSounds ? " [all]" : " [first+last 15]"}',
      () async {
        final all = sf
            .getActiveSounds()
            .where((r) => !(r.isStream && r.channels == 2))
            .toList();

        if (all.isEmpty) {
          stdout.writeln('  (no active 1-channel entries)');
          return;
        }

        final toCheck = testAll1ChannelSounds ? all : _firstAndLast15(all);
        stdout.writeln(
            '  Checking ${toCheck.length} / ${all.length} 1-channel entries...');

        final failures = <String>[];
        for (final r in toCheck) {
          final err = await _checkWav(sf.extractWav(r), r.name, tmpDir);
          if (err != null) failures.add(err);
        }
        expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
      },
      timeout: const Timeout(Duration(minutes: 15)),
    );
  });
}

// ── Main ─────────────────────────────────────────────────────────────────────

void main() {
  for (final MapEntry(key: (platform, version), value: dirPath)
      in _scanDirs.entries) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      test('[$platform/$version] scan dir exists: $dirPath',
          () => fail('Directory not found: $dirPath'));
      continue;
    }

    final lvlFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.lvl'))
        .map((f) => f.path)
        .toList()
      ..sort();

    if (lvlFiles.isEmpty) {
      test('[$platform/$version] at least one .lvl in $dirPath',
          () => fail('No .lvl files found in $dirPath'));
      continue;
    }

    for (final lvlPath in lvlFiles) {
      _registerLvlTests(lvlPath, platform, version);
    }
  }
}
