import 'dart:io';
import 'dart:typed_data';
import 'package:bf_sound_tool/bf_sound_tool.dart';
import 'package:test/test.dart';

// Minimal synthetic VAG ADPCM: N silent 16-byte blocks.
Uint8List _silentVag(int blocks) {
  final out = Uint8List(blocks * 16);
  // Last block: flags = 0x01 (loop end / end of stream marker).
  out[(blocks - 1) * 16 + 1] = 0x01;
  return out;
}

void main() {
  const pspFile = 'test/test_files/psp/nab.lvl';

  late Uint8List origBytes;
  late BattlefrontSoundFile sf;

  setUpAll(() {
    origBytes = File(pspFile).readAsBytesSync();
    sf = BattlefrontSoundFile(origBytes, 'psp', 'bf2');
  });

  group('PSP sample replacement — wpn_rep_pistol_fire', () {
    const entryName = 'wpn_rep_pistol_fire';
    final newAudio = _silentVag(32); // 512 bytes

    late Uint8List outBytes;
    late BattlefrontSoundFile outSf;
    late SoundRecord origRecord;
    late SoundRecord newRecord;

    setUpAll(() {
      origRecord = sf.getSound(entryName)!;
      outBytes = sf.replaceAudio(origRecord, newAudio);
      outSf = BattlefrontSoundFile(outBytes, 'psp', 'bf2');
      newRecord = outSf.getSound(entryName)!;
    });

    test('entry is found in original', () {
      expect(origRecord, isNotNull);
      expect(origRecord.skip, isFalse);
    });

    test('output file is smaller when replacement audio is smaller', () {
      expect(newAudio.length, lessThan(origRecord.dataSize));
      expect(outBytes.length, lessThan(origBytes.length));
    });

    test('dataSize updated to new audio length', () {
      expect(newRecord.dataSize, equals(newAudio.length));
    });

    test('sampleRate unchanged when no override', () {
      expect(newRecord.sampleRate, equals(origRecord.sampleRate));
    });

    test('bankIndex unchanged', () {
      expect(newRecord.bankIndex, equals(origRecord.bankIndex));
    });

    test('audio bytes at entry offset match replacement', () {
      final extracted = outSf.extractRawAudio(newRecord);
      expect(extracted, equals(newAudio));
    });

    test('sequential layout is correct after replacement', () {
      final dict  = Dictionary()..loadBuiltin();
      final root  = UcfParser.parse(outBytes);
      final banks = BankParser.parseBanks(root, outBytes, dict, platform: 'psp');
      final bank  = banks[newRecord.bankIndex];

      int readPos = bank.dataChunk.bodyOffset;
      for (final e in bank.entries) {
        if (e.skip) continue;
        expect(e.audioOffset, equals(readPos),
            reason: '${e.name} audioOffset mismatch');
        readPos += e.dataSize;
      }
    });

    test('bank-level data chunk size equals sum of entry sizes', () {
      final dict  = Dictionary()..loadBuiltin();
      final root  = UcfParser.parse(outBytes);
      final banks = BankParser.parseBanks(root, outBytes, dict, platform: 'psp');
      final bank  = banks[newRecord.bankIndex];

      final total = bank.entries
          .where((e) => !e.skip)
          .fold(0, (s, e) => s + e.dataSize);
      expect(bank.dataChunk.size, equals(total));
    });

    test('other banks are not modified', () {
      final dict    = Dictionary()..loadBuiltin();
      final origRoot = UcfParser.parse(origBytes);
      final outRoot  = UcfParser.parse(outBytes);
      final origBanks = BankParser.parseBanks(origRoot, origBytes, dict, platform: 'psp');
      final outBanks  = BankParser.parseBanks(outRoot,  outBytes,  dict, platform: 'psp');

      for (int b = 0; b < origBanks.length; b++) {
        if (b == origRecord.bankIndex) continue;
        expect(outBanks[b].dataChunk.size, equals(origBanks[b].dataChunk.size),
            reason: 'Bank ${b+1} data chunk size changed unexpectedly');
      }
    });
  });

  group('PSP sample replacement — sampleRate override', () {
    const entryName = 'wpn_rep_pistol_fire';
    const overrideRate = 6004;
    final newAudio = _silentVag(16); // 256 bytes

    late Uint8List outBytes;
    late SoundRecord newRecord;

    setUpAll(() {
      final record = sf.getSound(entryName)!;
      outBytes = sf.replaceAudio(record, newAudio, newSampleRate: overrideRate);
      final outSf = BattlefrontSoundFile(outBytes, 'psp', 'bf2');
      newRecord = outSf.getSound(entryName)!;
    });

    test('sampleRate patched to override value', () {
      expect(newRecord.sampleRate, equals(overrideRate));
    });

    test('dataSize still correct with rate override', () {
      expect(newRecord.dataSize, equals(newAudio.length));
    });
  });

  group('PSP sample replacement — chained (two entries)', () {
    final audio1 = _silentVag(20); // 320 bytes — for chaingun
    final audio2 = _silentVag(10); // 160 bytes — for pistol

    late Uint8List finalBytes;

    setUpAll(() {
      // First replacement.
      final rec1 = sf.getSound('wpn_chaingun_fire01')!;
      final mid  = BattlefrontSoundFile(
          sf.replaceAudio(rec1, audio1), 'psp', 'bf2');
      // Second replacement on top.
      final rec2 = mid.getSound('wpn_rep_pistol_fire')!;
      finalBytes = mid.replaceAudio(rec2, audio2);
    });

    test('both entries have correct dataSize', () {
      final outSf = BattlefrontSoundFile(finalBytes, 'psp', 'bf2');
      expect(outSf.getSound('wpn_chaingun_fire01')!.dataSize, equals(audio1.length));
      expect(outSf.getSound('wpn_rep_pistol_fire')!.dataSize,  equals(audio2.length));
    });

    test('sequential layout correct after two replacements', () {
      final dict  = Dictionary()..loadBuiltin();
      final root  = UcfParser.parse(finalBytes);
      final banks = BankParser.parseBanks(root, finalBytes, dict, platform: 'psp');

      for (final bank in banks) {
        int readPos = bank.dataChunk.bodyOffset;
        for (final e in bank.entries) {
          if (e.skip) continue;
          expect(e.audioOffset, equals(readPos),
              reason: '${e.name} audioOffset mismatch after chained replace');
          readPos += e.dataSize;
        }
      }
    });

    test('audio bytes correct for both entries', () {
      final outSf = BattlefrontSoundFile(finalBytes, 'psp', 'bf2');
      expect(outSf.extractRawAudio(outSf.getSound('wpn_chaingun_fire01')!), equals(audio1));
      expect(outSf.extractRawAudio(outSf.getSound('wpn_rep_pistol_fire')!),  equals(audio2));
    });
  });
}
