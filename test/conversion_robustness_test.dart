
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bf_sound_tool/bf_sound_tool.dart';
import 'package:bf_sound_tool/src/vag_decoder.dart';
import 'package:bf_sound_tool/src/wav_parser.dart';

void main() {
  group('AT3 Conversion Robustness', () {
    
    test('VagDecoder should not crash or loop with zero interleave', () {
      final dummyData = Uint8List(1024); // Zeroed data
      
      // This would have previously entered an infinite loop or crashed
      // if interleave was 0 for a stereo stream.
      expect(() => VagDecoder.decode(dummyData, 2, 0), returnsNormally);
      
      final result = VagDecoder.decode(dummyData, 2, 0);
      expect(result, isNotEmpty);
    });

    test('WavParser.readInfo identifies ATRAC3+ format tags', () {
      // Manually craft a minimal RIFF header with Sony AT3+ format (0x0270)
      final header = Uint8List(44);
      header.setRange(0, 4, 'RIFF'.codeUnits);
      header.setRange(8, 12, 'WAVE'.codeUnits);
      header.setRange(12, 16, 'fmt '.codeUnits);
      header[16] = 16; // fmt chunk size
      header[20] = 0x70; // format 0x0270 (AT3+)
      header[21] = 0x02;
      
      final info = WavParser.readInfo(header);
      expect(info, isNotNull);
      expect(info!.format, equals(0x0270));
    });

    test('Logic check: Identify already converted RIFF data', () {
      // Simulate what the tool does in bin/bf_sound_tool.dart
      final riffData = Uint8List(100);
      riffData.setRange(0, 4, 'RIFF'.codeUnits);
      riffData.setRange(8, 12, 'WAVE'.codeUnits);
      riffData.setRange(12, 16, 'fmt '.codeUnits);
      riffData[20] = 0x70; 
      riffData[21] = 0x02;

      final nonRiffData = Uint8List(100);
      nonRiffData[0] = 0x0C; // Typical VAG header byte

      bool isAlreadyConverted(Uint8List data) {
        if (data.length > 12 && data[0] == 0x52 && data[1] == 0x49) {
          final info = WavParser.readInfo(data);
          return info != null && (info.format == 0x0270 || info.format == 0xFFFE);
        }
        return false;
      }

      expect(isAlreadyConverted(riffData), isTrue, reason: 'Should detect AT3+ RIFF');
      expect(isAlreadyConverted(nonRiffData), isFalse, reason: 'Should not detect VAG as RIFF');
    });
  });
}
