import 'dart:typed_data';
import 'package:bf_sound_tool/bf_sound_tool.dart';

/// Examples for the "PSP BF2 Sound Swapper" web tool.
/// 
/// These examples assume a web context where files are received as [Uint8List]
/// (e.g. from an <input type="file"> or a Drag & Drop 'drop zone').

// ── Use Case 1: Auto Replacement ─────────────────────────────────────────────
// User drags LVL and ZIP. Tool matches names and auto-converts.

void useCase1_AutoReplace(Uint8List lvlBytes, Map<String, Uint8List> wavsFromZip) {
  // 1. Initialize the sound file (PSP BF2)
  final sf = BattlefrontSoundFile(lvlBytes, 'psp', 'bf2');

  // 2. Build the replacement map
  final replacements = <SoundRecord, Uint8List>{};
  
  for (final record in sf.getActiveSounds()) {
    // Look for a matching WAV in the ZIP entries (case-insensitive)
    final match = wavsFromZip.entries
        .where((e) => e.key.toLowerCase() == '${record.name.toLowerCase()}.wav')
        .firstOrNull;

    if (match != null) {
      replacements[record] = match.value;
    }
  }

  // 3. Perform batch replacement
  // Library automatically handles:
  // - Resampling to match the original entry's Hz
  // - Mono downmixing
  // - SPU ADPCM (VAG) encoding for samples
  // - ATRAC3plus passthrough for streams
  final newLvlBytes = sf.replaceManyWithWav(replacements);

  // 4. Trigger download in browser
  // _downloadFile('shell_replaced.lvl', newLvlBytes);
}


// ── Use Case 2: Manual Per-File Sample Rates ─────────────────────────────────
// User manually enters the target sample rates for each replacement sound.

void useCase2_ManualPerFileRates(
  Uint8List lvlBytes, 
  Map<String, Uint8List> wavsFromZip,
  Map<String, int> userDefinedRates, // e.g. {"saberon": 22050, "saberoff": 11025}
) {
  final sf = BattlefrontSoundFile(lvlBytes, 'psp', 'bf2');
  
  final replacements = <SoundRecord, Uint8List>{};
  final overrides = <SoundRecord, int>{};

  for (final entry in wavsFromZip.entries) {
    final name = entry.key.replaceAll('.wav', '');
    final record = sf.getSound(name);
    
    if (record != null) {
      replacements[record] = entry.value;
      
      // If the user specified a rate for this sound, add it to overrides
      if (userDefinedRates.containsKey(name)) {
        overrides[record] = userDefinedRates[name]!;
      }
    }
  }

  // replaceManyWithWav uses the override if present, else matches original entry.
  final newLvlBytes = sf.replaceManyWithWav(replacements, newSampleRates: overrides);
}


// ── Use Case 2.1: Global Sample Rate Override ────────────────────────────────
// User enters one target sample rate for ALL replacement sound files.

void useCase2_1_GlobalRate(
  Uint8List lvlBytes, 
  Map<String, Uint8List> wavsFromZip,
  int globalRate, // e.g. 11025
) {
  final sf = BattlefrontSoundFile(lvlBytes, 'psp', 'bf2');
  
  final replacements = <SoundRecord, Uint8List>{};
  final overrides = <SoundRecord, int>{};

  for (final entry in wavsFromZip.entries) {
    final name = entry.key.replaceAll('.wav', '');
    final record = sf.getSound(name);
    
    if (record != null) {
      replacements[record] = entry.value;
      overrides[record] = globalRate; // Apply same rate to all
    }
  }

  final newLvlBytes = sf.replaceManyWithWav(replacements, newSampleRates: overrides);
}


// ── UI Helper: Display Inner File Info ───────────────────────────────────────
// Desirable to display the inner file names, sizes, sample rates before processing.

void ui_DisplayFileInfo(Map<String, Uint8List> wavsFromZip) {
  for (final entry in wavsFromZip.entries) {
    final info = WavParser.readInfo(entry.value);
    if (info != null) {
      print('File: ${entry.key}');
      print('  Size: ${entry.value.length} bytes');
      print('  Native Rate: ${info.sampleRate} Hz');
      print('  Channels: ${info.channels}');
    }
  }
}
