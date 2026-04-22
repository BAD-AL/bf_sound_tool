import 'dart:io';
import 'dart:typed_data';
import 'package:bf_sound_tool/src/ucf_parser.dart';
import 'package:bf_sound_tool/src/ucf_chunk.dart';
import 'package:test/test.dart';

void main() {
  late Uint8List hotLvl;
  late UcfChunk root;

  setUpAll(() {
    hotLvl = File('test/test_files/xbox/hot.lvl').readAsBytesSync();
    root = UcfParser.parse(hotLvl);
  });

  group('root chunk', () {
    test('ID is ucfb', () {
      expect(root.id, equals(UcfParser.idUcfb));
    });

    test('size covers entire file minus 8-byte header', () {
      expect(root.size, equals(hotLvl.length - 8));
    });

    test('has children', () {
      expect(root.hasChildren, isTrue);
    });
  });

  group('bank 1 — streams (inside emo_)', () {
    late UcfChunk info1;
    late UcfChunk data1;

    setUp(() {
      // info and data for bank 1 are found in allChunks()
      final all = root.allChunks().toList();
      info1 = all.firstWhere(
        (c) => c.id == UcfParser.idInfo && c.offset == 0x18,
      );
      data1 = all.firstWhere(
        (c) => c.id == UcfParser.idData && c.bodyOffset == 0x800,
      );
    });

    test('bank 1 info chunk at expected offset', () {
      expect(info1.offset, equals(0x18));
    });

    test('bank 1 info size matches known value', () {
      expect(info1.size, equals(2008));
    });

    test('bank 1 data chunk header at 0x7f8', () {
      expect(data1.offset, equals(0x7f8));
    });

    test('bank 1 data body at 0x800', () {
      expect(data1.bodyOffset, equals(0x800));
    });

    test('bank 1 data size matches known value', () {
      expect(data1.size, equals(44974080));
    });

    test('bank 1 data is a leaf (no children)', () {
      expect(data1.hasChildren, isFalse);
    });
  });

  group('bank 2 — samples (inside SampleBank)', () {
    late UcfChunk info2;
    late UcfChunk data2;

    setUp(() {
      final all = root.allChunks().toList();
      info2 = all.firstWhere(
        (c) => c.id == UcfParser.idInfo && c.offset == 0x2ae4820,
      );
      data2 = all.firstWhere(
        (c) => c.id == UcfParser.idData && c.bodyOffset == 0x2aeb008,
      );
    });

    test('bank 2 info chunk at expected offset', () {
      expect(info2.offset, equals(0x2ae4820));
    });

    test('bank 2 info size matches known value', () {
      expect(info2.size, equals(26584));
    });

    test('bank 2 data chunk header at 0x2aeb000', () {
      expect(data2.offset, equals(0x2aeb000));
    });

    test('bank 2 data body at 0x2aeb008', () {
      expect(data2.bodyOffset, equals(0x2aeb008));
    });

    test('bank 2 data size matches known value', () {
      expect(data2.size, equals(5660672));
    });

    test('bank 2 data is a leaf (no children)', () {
      expect(data2.hasChildren, isFalse);
    });
  });

  group('tree structure sanity', () {
    test('exactly 2 info chunks exist in file', () {
      final infos = root.allChunks().where((c) => c.id == UcfParser.idInfo);
      expect(infos.length, equals(2));
    });

    test('exactly 2 data chunks exist in file', () {
      final datas = root.allChunks().where((c) => c.id == UcfParser.idData);
      expect(datas.length, equals(2));
    });

    test('each info chunk has a data chunk sibling at the same parent level', () {
      // Walk all parents looking for (info, data) sibling pairs
      int bankPairCount = 0;
      for (final chunk in root.allChunks()) {
        if (chunk.hasChildren) {
          final ids = chunk.children.map((c) => c.id).toList();
          if (ids.contains(UcfParser.idInfo) && ids.contains(UcfParser.idData)) {
            bankPairCount++;
          }
        }
      }
      expect(bankPairCount, equals(2));
    });
  });
}
