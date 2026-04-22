import 'dart:typed_data';
import 'package:bf_sound_tool/src/byte_reader.dart';
import 'package:test/test.dart';

void main() {
  group('ByteReader', () {
    test('readUint8 reads single byte and advances position', () {
      final r = ByteReader(Uint8List.fromList([0xAB, 0xCD]));
      expect(r.readUint8(), equals(0xAB));
      expect(r.position, equals(1));
      expect(r.readUint8(), equals(0xCD));
      expect(r.position, equals(2));
    });

    test('readUint16 reads little-endian uint16', () {
      // 0x0200 stored LE = [0x00, 0x02]
      final r = ByteReader(Uint8List.fromList([0x02, 0x00]));
      expect(r.readUint16(), equals(2));

      // Channel count 2 from hot.lvl bank1 header
      final r2 = ByteReader(Uint8List.fromList([0x02, 0x00, 0xFF]));
      expect(r2.readUint16(), equals(2));
      expect(r2.position, equals(2));
    });

    test('readUint32 reads little-endian uint32', () {
      // ucfb root chunk size: bytes [0x18, 0x0F, 0x0D, 0x03] = 0x030D0F18 = 51187480
      final r = ByteReader(Uint8List.fromList([0x18, 0x0F, 0x0D, 0x03]));
      expect(r.readUint32(), equals(0x030d0f18));
      expect(r.position, equals(4));
    });

    test('readUint32 handles large values (high bit set)', () {
      // 0xD872E2A5 = audio data chunk ID
      final r = ByteReader(Uint8List.fromList([0xA5, 0xE2, 0x72, 0xD8]));
      expect(r.readUint32(), equals(0xD872E2A5));
    });

    test('readUint32 result is always non-negative', () {
      final r = ByteReader(Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]));
      final v = r.readUint32();
      expect(v, equals(0xFFFFFFFF));
      expect(v, greaterThanOrEqualTo(0));
    });

    test('readBytes returns correct slice and advances position', () {
      final r = ByteReader(Uint8List.fromList([0x10, 0x20, 0x30, 0x40, 0x50]));
      final bytes = r.readBytes(3);
      expect(bytes, equals([0x10, 0x20, 0x30]));
      expect(r.position, equals(3));
    });

    test('seek sets absolute position', () {
      final r = ByteReader(Uint8List.fromList([0x01, 0x02, 0x03, 0x04]));
      r.seek(2);
      expect(r.position, equals(2));
      expect(r.readUint8(), equals(0x03));
    });

    test('skip advances position by count', () {
      final r = ByteReader(Uint8List.fromList([0x01, 0x02, 0x03, 0x04]));
      r.skip(2);
      expect(r.position, equals(2));
    });

    test('peekUint32 reads without moving position', () {
      final r = ByteReader(Uint8List.fromList([0x18, 0x0F, 0x0D, 0x03, 0xFF]));
      expect(r.peekUint32(), equals(0x030d0f18));
      expect(r.position, equals(0));
    });

    test('peekUint32 at explicit offset', () {
      final r = ByteReader(Uint8List.fromList([0x00, 0x00, 0x62, 0x66, 0x63, 0x75]));
      // 'ucfb' LE at offset 2 = bytes [0x62, 0x66, 0x63, 0x75] = 0x75636662
      expect(r.peekUint32(2), equals(0x75636662));
      expect(r.position, equals(0));
    });

    test('isAtEnd reports correctly', () {
      final r = ByteReader(Uint8List.fromList([0x01, 0x02]));
      expect(r.isAtEnd, isFalse);
      r.readUint8();
      r.readUint8();
      expect(r.isAtEnd, isTrue);
    });

    test('length returns total byte count', () {
      final r = ByteReader(Uint8List.fromList([1, 2, 3]));
      expect(r.length, equals(3));
    });

    test('slice creates sub-reader over a range', () {
      final r = ByteReader(Uint8List.fromList([0x00, 0xAA, 0xBB, 0xCC, 0x00]));
      final sub = r.slice(1, 3);
      expect(sub.length, equals(3));
      expect(sub.readUint8(), equals(0xAA));
      expect(sub.readUint8(), equals(0xBB));
      expect(sub.readUint8(), equals(0xCC));
    });

    test('multiple sequential reads track position correctly', () {
      // Simulate reading a small UCF chunk header: ID=ucfb, size=51187480
      // ucfb LE = 0x62666375 = bytes [0x75, 0x63, 0x66, 0x62]
      final r = ByteReader(Uint8List.fromList([
        0x75, 0x63, 0x66, 0x62, // 'ucfb' as LE uint32 = 0x62666375
        0x18, 0x0F, 0x0D, 0x03, // size = 51187480
      ]));
      expect(r.readUint32(), equals(0x62666375)); // chunk ID
      expect(r.readUint32(), equals(51187480));   // chunk size
      expect(r.isAtEnd, isTrue);
    });
  });
}
