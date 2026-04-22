import 'package:bf_sound_tool/src/fnv_hash.dart';
import 'package:test/test.dart';

void main() {
  group('fnvHash', () {
    test('empty string returns offset basis', () {
      expect(fnvHash(''), equals(0x811c9dc5));
    });

    test('hash is case-insensitive (lowercase forced via | 0x20)', () {
      expect(fnvHash('HOT_AMB_WIND'), equals(fnvHash('hot_amb_wind')));
      expect(fnvHash('Hot_Amb_Wind'), equals(fnvHash('hot_amb_wind')));
    });

    test('known value: hot_amb_wind = 0x7a849cde', () {
      expect(fnvHash('hot_amb_wind'), equals(0x7a849cde));
    });

    test('known value: hot_amb_icecave = 0x08318f82', () {
      expect(fnvHash('hot_amb_icecave'), equals(0x08318f82));
    });

    test('known value: hot_amb_hangar = 0x8fa2a98b', () {
      expect(fnvHash('hot_amb_hangar'), equals(0x8fa2a98b));
    });

    test('result is always a valid unsigned 32-bit integer', () {
      for (final name in ['ucfb', 'emo_', 'test', 'a' * 64]) {
        final h = fnvHash(name);
        expect(h, greaterThanOrEqualTo(0));
        expect(h, lessThanOrEqualTo(0xFFFFFFFF));
      }
    });

    test('different strings produce different hashes', () {
      final hashes = {
        fnvHash('hot_amb_wind'),
        fnvHash('hot_amb_hangar'),
        fnvHash('hot_amb_icecave'),
      };
      expect(hashes.length, equals(3));
    });
  });
}
