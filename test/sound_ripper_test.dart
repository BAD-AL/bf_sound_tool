// Integration smoke test — updated as the library grows.
// Detailed unit tests live in fnv_hash_test.dart, byte_reader_test.dart, dictionary_test.dart.
import 'dart:typed_data';
import 'package:sound_ripper/sound_ripper.dart';
import 'package:test/test.dart';

void main() {
  test('library exports are accessible', () {
    expect(fnvHash('hot_amb_wind'), equals(0x7a849cde));

    final r = ByteReader(Uint8List.fromList([0xA5, 0xE2, 0x72, 0xD8]));
    expect(r.readUint32(), equals(0xD872E2A5));

    final d = Dictionary();
    d.addName('test');
    expect(d.resolve(fnvHash('test')), equals('test'));
  });
}
