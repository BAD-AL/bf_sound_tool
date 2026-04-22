import 'dart:io';
import 'dart:typed_data';
import 'package:sound_ripper/src/ucf_parser.dart';
import 'package:sound_ripper/src/bank_parser.dart';
import 'package:sound_ripper/src/dictionary.dart';
import 'package:test/test.dart';

void main() {
  late Uint8List fileBytes;
  late List<SoundBank> banks;

  setUpAll(() async {
    fileBytes = File('test/test_files/xbox/hot.lvl').readAsBytesSync();
    final root = UcfParser.parse(fileBytes);
    final dict = Dictionary()..loadBuiltin();
    banks = BankParser.parseBanks(root, fileBytes, dict, platform: 'xbox');
  });

  group('bank discovery', () {
    test('finds exactly 2 banks', () {
      expect(banks.length, equals(2));
    });
  });

  group('bank 1 — streams', () {
    late SoundBank bank1;
    setUp(() => bank1 = banks[0]);

    test('wavCount = 3', () => expect(bank1.wavCount, equals(3)));
    test('channels = 2', () => expect(bank1.channels, equals(2)));
    test('isStream = true', () => expect(bank1.isStream, isTrue));
    test('entry count = 3', () => expect(bank1.entries.length, equals(3)));

    test('hot_amb_wind name resolves', () {
      expect(bank1.entries[0].name, equals('hot_amb_wind'));
    });
    test('hot_amb_wind sample rate = 44100', () {
      expect(bank1.entries[0].sampleRate, equals(44100));
    });
    test('hot_amb_wind raw data size = 18931104', () {
      expect(bank1.entries[0].dataSize, equals(18931104));
    });
    test('hot_amb_wind padded read size = 18931712 (matches VB)', () {
      expect(bank1.entries[0].audioReadSize, equals(18931712));
    });
    test('hot_amb_wind audio offset = 0x800', () {
      expect(bank1.entries[0].audioOffset, equals(0x800));
    });
    test('hot_amb_wind skip = false', () {
      expect(bank1.entries[0].skip, isFalse);
    });

    test('hot_amb_icecave name resolves', () {
      expect(bank1.entries[1].name, equals('hot_amb_icecave'));
    });
    test('hot_amb_icecave sample rate = 44100', () {
      expect(bank1.entries[1].sampleRate, equals(44100));
    });
    test('hot_amb_icecave raw data size = 9425520', () {
      expect(bank1.entries[1].dataSize, equals(9425520));
    });
    test('hot_amb_icecave padded read size = 9426944 (matches VB)', () {
      expect(bank1.entries[1].audioReadSize, equals(9426944));
    });
    test('hot_amb_icecave audio offset = 0x1212800 (interleave-aligned)', () {
      expect(bank1.entries[1].audioOffset, equals(0x1212800));
    });

    test('hot_amb_hangar name resolves', () {
      expect(bank1.entries[2].name, equals('hot_amb_hangar'));
    });
    test('hot_amb_hangar audio offset = 0x1b12800 (interleave-aligned)', () {
      expect(bank1.entries[2].audioOffset, equals(0x1b12800));
    });
    test('hot_amb_hangar raw data size = 16552944', () {
      expect(bank1.entries[2].dataSize, equals(16552944));
    });
    test('hot_amb_hangar padded read size = 16553984 (matches VB)', () {
      expect(bank1.entries[2].audioReadSize, equals(16553984));
    });
  });

  group('bank 2 — samples', () {
    late SoundBank bank2;
    setUp(() => bank2 = banks[1]);

    test('wavCount = 512', () => expect(bank2.wavCount, equals(512)));
    test('isStream = false (high channel count)', () {
      expect(bank2.isStream, isFalse);
    });
    test('entry count = 512', () => expect(bank2.entries.length, equals(512)));

    test('saberon name resolves', () {
      expect(bank2.entries[0].name, equals('saberon'));
    });
    test('saberon sample rate = 22050', () {
      expect(bank2.entries[0].sampleRate, equals(22050));
    });
    test('saberon data size = 20412', () {
      expect(bank2.entries[0].dataSize, equals(20412));
    });
    test('saberon audio offset = 0x2aeb008', () {
      expect(bank2.entries[0].audioOffset, equals(0x2aeb008));
    });
    test('saberon skip = false', () {
      expect(bank2.entries[0].skip, isFalse);
    });

    test('saberoff audio offset = 0x2aeffc4', () {
      expect(bank2.entries[1].audioOffset, equals(0x2aeffc4));
    });
    test('saber_triple audio offset = 0x2af1e90', () {
      expect(bank2.entries[2].audioOffset, equals(0x2af1e90));
    });

    test('no entries skipped in hot.lvl', () {
      final skipped = bank2.entries.where((e) => e.skip).length;
      expect(skipped, equals(0));
    });
  });

  group('aliases — Xbox geo.lvl', () {
    late List<SoundBank> geobanks;

    setUpAll(() {
      final bytes = File('test/test_files/xbox/geo.lvl').readAsBytesSync();
      final root = UcfParser.parse(bytes);
      final dict = Dictionary()..loadBuiltin();
      geobanks = BankParser.parseBanks(root, bytes, dict, platform: 'xbox');
    });

    test('has alias entries', () {
      final aliases = geobanks
          .expand((b) => b.entries)
          .where((e) => e.aliasFor != null);
      expect(aliases, isNotEmpty);
    });

    test('mvt_trooper_dirt_lgBF_02 aliases mvt_trooper_dirt_lgBF_01', () {
      final entry = geobanks
          .expand((b) => b.entries)
          .firstWhere((e) => e.name == 'mvt_trooper_dirt_lgBF_02');
      expect(entry.skip, isTrue);
      expect(entry.aliasFor, equals('mvt_trooper_dirt_lgBF_01'));
    });

    test('mvt_trooper_dirt_lgBF_03 aliases mvt_trooper_dirt_lgBF_01', () {
      final entry = geobanks
          .expand((b) => b.entries)
          .firstWhere((e) => e.name == 'mvt_trooper_dirt_lgBF_03');
      expect(entry.aliasFor, equals('mvt_trooper_dirt_lgBF_01'));
    });

    test('non-alias skipped entries have aliasFor == null', () {
      // hot.lvl xbox has no skips at all; geo.lvl skips should all be aliases
      final skippedWithoutAlias = geobanks
          .expand((b) => b.entries)
          .where((e) => e.skip && e.aliasFor == null);
      expect(skippedWithoutAlias, isEmpty);
    });
  });

  group('aliases — PS2 HOT.LVL', () {
    late List<SoundBank> hotPs2Banks;

    setUpAll(() {
      final bytes = File('test/test_files/ps2/HOT.LVL').readAsBytesSync();
      final root = UcfParser.parse(bytes);
      final dict = Dictionary()..loadBuiltin();
      hotPs2Banks = BankParser.parseBanks(root, bytes, dict, platform: 'ps2');
    });

    test('has alias entries', () {
      final aliases = hotPs2Banks
          .expand((b) => b.entries)
          .where((e) => e.aliasFor != null);
      expect(aliases, isNotEmpty);
    });

    test('ltsaberswing03 aliases ltsaberswing02', () {
      final entry = hotPs2Banks
          .expand((b) => b.entries)
          .firstWhere((e) => e.name == 'ltsaberswing03');
      expect(entry.skip, isTrue);
      expect(entry.aliasFor, equals('ltsaberswing02'));
    });

    test('force_push_impact aliases force_push_fire', () {
      final entry = hotPs2Banks
          .expand((b) => b.entries)
          .firstWhere((e) => e.name == 'force_push_impact');
      expect(entry.aliasFor, equals('force_push_fire'));
    });

    test('droid_probe_beeps_02 through _05 all alias droid_probe_beeps_01', () {
      final entries = hotPs2Banks
          .expand((b) => b.entries)
          .where((e) => RegExp(r'droid_probe_beeps_0[2-5]').hasMatch(e.name))
          .toList();
      expect(entries.length, equals(4));
      for (final e in entries) {
        expect(e.aliasFor, equals('droid_probe_beeps_01'));
      }
    });

    test('PC hot.lvl entries have no aliases', () {
      final pcBytes = File('test/test_files/pc/hot.lvl').readAsBytesSync();
      final pcRoot = UcfParser.parse(pcBytes);
      final pcDict = Dictionary()..loadBuiltin();
      final pcBanks =
          BankParser.parseBanks(pcRoot, pcBytes, pcDict, platform: 'pc');
      final aliases =
          pcBanks.expand((b) => b.entries).where((e) => e.aliasFor != null);
      expect(aliases, isEmpty);
    });
  });
}
