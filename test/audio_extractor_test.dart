import 'dart:io';
import 'dart:typed_data';
import 'package:bf_sound_tool/src/ucf_parser.dart';
import 'package:bf_sound_tool/src/bank_parser.dart';
import 'package:bf_sound_tool/src/audio_extractor.dart';
import 'package:bf_sound_tool/src/dictionary.dart';
import 'package:test/test.dart';

void main() {
  late Uint8List fileBytes;
  late List<SoundBank> banks;

  setUpAll(() {
    fileBytes = File('test/test_files/xbox/hot.lvl').readAsBytesSync();
    final root = UcfParser.parse(fileBytes);
    final dict = Dictionary()..loadBuiltin();
    banks = BankParser.parseBanks(root, fileBytes, dict, platform: 'xbox');
  });

  group('bank 1 stream extraction', () {
    test('hot_amb_wind extracted length matches VB output size', () {
      final bytes = AudioExtractor.extract(fileBytes, banks[0].entries[0]);
      expect(bytes.length, equals(18931712));
    });

    test('hot_amb_icecave extracted length matches VB output size', () {
      final bytes = AudioExtractor.extract(fileBytes, banks[0].entries[1]);
      expect(bytes.length, equals(9426944));
    });

    test('hot_amb_hangar extracted length matches VB output size', () {
      final bytes = AudioExtractor.extract(fileBytes, banks[0].entries[2]);
      expect(bytes.length, equals(16553984));
    });

    test('hot_amb_wind audio data is non-zero (not silent/empty)', () {
      final bytes = AudioExtractor.extract(fileBytes, banks[0].entries[0]);
      final nonZero = bytes.any((b) => b != 0);
      expect(nonZero, isTrue);
    });

    test('stream extraction returns a view into the original buffer', () {
      // Uint8List.sublistView shares the underlying data — first byte should match.
      final entry = banks[0].entries[0];
      final view = AudioExtractor.extract(fileBytes, entry);
      expect(view[0], equals(fileBytes[entry.audioOffset]));
      expect(view.last, equals(fileBytes[entry.audioOffset + entry.audioReadSize - 1]));
    });
  });

  group('bank 2 sample extraction', () {
    test('saberon extracted length equals raw data size (no padding)', () {
      final entry = banks[1].entries[0];
      final bytes = AudioExtractor.extract(fileBytes, entry);
      expect(bytes.length, equals(entry.dataSize));
      expect(bytes.length, equals(20412));
    });

    test('saberoff extracted length = 7884', () {
      final bytes = AudioExtractor.extract(fileBytes, banks[1].entries[1]);
      expect(bytes.length, equals(7884));
    });

    test('total extracted bytes for all bank 2 entries fits within data chunk', () {
      int total = 0;
      for (final entry in banks[1].entries) {
        total += entry.audioReadSize;
      }
      // Entries fill the chunk body; a small trailing pad may remain.
      expect(total, lessThanOrEqualTo(banks[1].dataChunk.size));
      expect(total, greaterThan(banks[1].dataChunk.size - 4096));
    });

    test('saberon audio data is non-zero', () {
      final bytes = AudioExtractor.extract(fileBytes, banks[1].entries[0]);
      expect(bytes.any((b) => b != 0), isTrue);
    });
  });
}
