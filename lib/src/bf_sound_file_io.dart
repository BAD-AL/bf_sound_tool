import 'dart:io';
import 'package:path/path.dart' as p;
import 'battlefront_sound_file.dart';
import 'sound_record.dart';

/// I/O extensions for [BattlefrontSoundFile], separated to maintain 
/// web compatibility of the core library.
extension BattlefrontSoundFileIo on BattlefrontSoundFile {
  /// Scans [folder] for .wav files matching entry names in this LVL.
  ///
  /// Returns a map of SoundRecord to File.
  /// Entries that are aliases or not found in the LVL are ignored.
  Map<SoundRecord, File> mapWavsInFolder(Directory folder) {
    if (!folder.existsSync()) return {};
    final wavFiles = folder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.wav'))
        .toList();

    final result = <SoundRecord, File>{};
    final activeMap = <String, SoundRecord>{};
    for (final r in getAllSounds()) {
      if (!r.skip) activeMap[r.name] = r;
    }

    for (final file in wavFiles) {
      final name = p.basenameWithoutExtension(file.path);
      final record = activeMap[name];
      if (record != null) {
        result[record] = file;
      }
    }
    return result;
  }
}
