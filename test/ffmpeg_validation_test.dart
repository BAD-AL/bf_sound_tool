import 'dart:io';
import 'package:sound_ripper/sound_ripper.dart';
import 'package:test/test.dart';

Future<int> _ffmpegCheck(String wavPath) async {
  final outPath = '$wavPath.check.wav';
  final result = await Process.run('ffmpeg', [
    '-y', '-i', wavPath,
    '-f', 'wav', '-c:a', 'pcm_s16le',
    outPath,
  ]);
  if (File(outPath).existsSync()) File(outPath).deleteSync();
  return result.exitCode;
}

void main() {
  late BattlefrontSoundFile sf;
  late Directory tmpDir;

  setUpAll(() async {
    final bytes = File('test/test_files/xbox/hot.lvl').readAsBytesSync();
    sf = BattlefrontSoundFile(bytes, 'xbox', 'bf2');
    tmpDir = Directory.systemTemp.createTempSync('sound_ripper_ffmpeg_');
  });

  tearDownAll(() => tmpDir.deleteSync(recursive: true));

  Future<int> checkByName(String name) async {
    final wav = sf.extractWavByName(name);
    final path = '${tmpDir.path}/$name.wav';
    File(path).writeAsBytesSync(wav);
    return _ffmpegCheck(path);
  }

  group('bank 1 streams (Xbox ADPCM)', () {
    test('hot_amb_wind decodes without error', () async {
      expect(await checkByName('hot_amb_wind'), equals(0));
    });
    test('hot_amb_icecave decodes without error', () async {
      expect(await checkByName('hot_amb_icecave'), equals(0));
    });
    test('hot_amb_hangar decodes without error', () async {
      expect(await checkByName('hot_amb_hangar'), equals(0));
    });
  });

  group('all _amb_ entries decode without error', () {
    late List<String> ambNames;

    setUpAll(() {
      ambNames = sf
          .getActiveSounds()
          .where((r) => r.name.contains('_amb_'))
          .map((r) => r.name)
          .toList();
      expect(ambNames, isNotEmpty, reason: 'no _amb_ entries found');
    });

    test('all _amb_ entries pass ffmpeg', () async {
      final failures = <String>[];
      for (final name in ambNames) {
        final code = await checkByName(name);
        if (code != 0) failures.add('$name | ffmpeg exit $code');
      }
      expect(failures, isEmpty, reason: '\n${failures.join('\n')}');
    });
  });

  group('bank 2 samples (Xbox ADPCM)', () {
    for (final name in [
      'saberon',
      'saberoff',
      'force_push_fire',
      'exp_ord_grenade01',
      'crtr_vader_breath_lp',
      'lightning_large',
    ]) {
      test('$name decodes without error', () async {
        expect(await checkByName(name), equals(0));
      });
    }
  });
}
