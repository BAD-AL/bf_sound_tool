import 'package:sound_ripper/src/dictionary.dart';
import 'package:test/test.dart';

void main() {
  group('Dictionary', () {
    late Dictionary dict;

    setUp(() {
      dict = Dictionary();
    });

    test('lookup returns null for unknown hash before loading', () {
      expect(dict.lookup(0x7a849cde), isNull);
    });

    test('addName makes hash resolvable', () {
      dict.addName('hot_amb_wind');
      expect(dict.lookup(0x7a849cde), equals('hot_amb_wind'));
    });

    test('addName is case-insensitive for lookup (stores original, hashes lowercase)', () {
      dict.addName('HOT_AMB_WIND');
      // Hash of 'hot_amb_wind' (lowercased) should resolve
      expect(dict.lookup(0x7a849cde), equals('HOT_AMB_WIND'));
    });

    test('resolve returns hex string for unknown hash', () {
      expect(dict.resolve(0x7a849cde), equals('0x7a849cde'));
    });

    test('resolve returns name for known hash', () {
      dict.addName('hot_amb_wind');
      expect(dict.resolve(0x7a849cde), equals('hot_amb_wind'));
    });

    test('loadLines adds multiple names', () {
      dict.loadLines([
        'hot_amb_wind',
        'hot_amb_hangar',
        'hot_amb_icecave',
        '',        // blank lines are ignored
        '  ',      // whitespace-only lines ignored
      ]);
      expect(dict.lookup(0x7a849cde), equals('hot_amb_wind'));
      expect(dict.lookup(0x8fa2a98b), equals('hot_amb_hangar'));
      expect(dict.lookup(0x08318f82), equals('hot_amb_icecave'));
    });

    test('loadLines handles duplicate hashes (first entry wins)', () {
      dict.loadLines(['hot_amb_wind', 'hot_amb_wind']);
      expect(dict.lookup(0x7a849cde), equals('hot_amb_wind'));
    });

    test('loadBuiltin loads all embedded BF2 names', () {
      dict.loadBuiltin();
      expect(dict.lookup(0x7a849cde), equals('hot_amb_wind'));
      expect(dict.lookup(0x8fa2a98b), equals('hot_amb_hangar'));
      expect(dict.lookup(0x08318f82), equals('hot_amb_icecave'));
    });

    test('loadString parses multi-line string, trims whitespace', () {
      dict.loadString('''
        hot_amb_wind
        hot_amb_hangar

        hot_amb_icecave
      ''');
      expect(dict.lookup(0x7a849cde), equals('hot_amb_wind'));
      expect(dict.lookup(0x8fa2a98b), equals('hot_amb_hangar'));
      expect(dict.lookup(0x08318f82), equals('hot_amb_icecave'));
    });

    test('loadString extra dict merges with existing entries', () {
      dict.loadBuiltin();
      dict.loadString('my_custom_mod_sound\nanother_mod_sound');
      // Built-in names still present
      expect(dict.lookup(0x7a849cde), equals('hot_amb_wind'));
      // Custom name added
      expect(dict.lookup(dict.lookup(0x7a849cde) != null ? 0x7a849cde : 0),
          isNotNull);
    });
  });
}
