// Example: using the sound_ripper library API
//
// Run from the sound_ripper project root:
//   dart API/example.dart
//
// Requires a hot.lvl file at test/test_files/xbox/hot.lvl

import 'dart:io';
import 'package:sound_ripper/sound_ripper.dart';

void main() {
  // ── 1. Parse a sound file ─────────────────────────────────────────────────
  //
  // The built-in dictionary (33 000+ BF1/BF2 names) is always loaded.
  // Pass extraDictionary to add modded or project-specific names.

  const lvlPath = 'test/test_files/xbox/hot.lvl';
  final bytes = File(lvlPath).readAsBytesSync();

  // Minimal — built-in dictionary only:
  final sf = BattlefrontSoundFile(bytes, 'xbox', 'bf2');

  // With extra names for a mod:
  // final sf = BattlefrontSoundFile(bytes, 'xbox', 'bf2',
  //   extraDictionary: '''
  //     my_custom_sound
  //     another_mod_sound
  //   ''',
  // );

  // ── 3. List all sounds ────────────────────────────────────────────────────

  final all = sf.getAllSounds();
  print('\n=== All sounds (${all.length} total) ===');
  for (final r in all) {
    final skipTag = r.skip ? ' [SKIP]' : '';
    print('  [bank ${r.bankIndex + 1}] ${r.typeLabel.padRight(6)} '
        '${r.name.padRight(36)} '
        '${r.sampleRate.toString().padLeft(6)} Hz  '
        '${r.channelLabel.padRight(6)}  '
        '${r.formattedOffset}$skipTag');
  }

  // ── 4. Query a specific sound by name ─────────────────────────────────────

  print('\n=== Look up "saberon" ===');
  final record = sf.getSound('saberon');
  if (record == null) {
    print('  Not found.');
  } else {
    print('  $record');
    print('  type:       ${record.typeLabel}');
    print('  channels:   ${record.channels} (${record.channelLabel})');
    print('  sampleRate: ${record.sampleRate} Hz');
    print('  dataSize:   ${record.dataSize} bytes');
    print('  audioReadSize: ${record.audioReadSize} bytes');
    print('  audioOffset:   ${record.formattedOffset}');
    print('  skip:       ${record.skip}');
  }

  // ── 5. Extract a WAV by SoundRecord ───────────────────────────────────────
  //
  // Preferred when you already have the record — no second name scan.

  if (record != null && !record.skip) {
    print('\n=== Extract WAV by SoundRecord ===');
    final wav = sf.extractWav(record);
    final outPath = '/tmp/${record.name}.wav';
    File(outPath).writeAsBytesSync(wav);
    print('  Written: $outPath (${wav.length} bytes)');
  }

  // ── 6. Extract a WAV by name (convenience overload) ───────────────────────
  //
  // Handy one-liner when you know the name is present.
  // Throws ArgumentError if the name is not found.

  print('\n=== Extract WAV by name ===');
  try {
    final wav = sf.extractWavByName('hot_amb_wind');
    final outPath = '/tmp/hot_amb_wind.wav';
    File(outPath).writeAsBytesSync(wav);
    print('  Written: $outPath (${wav.length} bytes)');
  } on ArgumentError catch (e) {
    print('  Error: $e');
  }

  // ── 7. Extract raw audio bytes (no WAV header) ────────────────────────────
  //
  // Useful if you want to feed data to your own audio pipeline or container.

  if (record != null && !record.skip) {
    print('\n=== Extract raw audio bytes ===');
    final raw = sf.extractRawAudio(record);
    print('  Raw bytes for "${record.name}": ${raw.length}');
  }

  // ── 8. Batch extract all active sounds ────────────────────────────────────

  print('\n=== Batch extract all active sounds ===');
  final outDir = Directory('/tmp/sound_ripper_example');
  outDir.createSync(recursive: true);

  int extracted = 0;
  int skipped = 0;

  for (final r in sf.getActiveSounds()) {
    // PC/PS2 ambient stereo streams need deinterleaving into two files.
    if (sf.platform != 'xbox' && r.name.contains('_amb_') && r.channels == 2) {
      final (front, back) = sf.extractAmbWavs(r);
      File('${outDir.path}/${r.name}_fnt.wav').writeAsBytesSync(front);
      File('${outDir.path}/${r.name}_bck.wav').writeAsBytesSync(back);
      print('  ${r.name} → _fnt.wav + _bck.wav');
    } else {
      final wav = sf.extractWav(r);
      File('${outDir.path}/${r.name}.wav').writeAsBytesSync(wav);
    }
    extracted++;
  }

  skipped = sf.getAllSounds().where((r) => r.skip).length;

  print('  Done. Extracted: $extracted  Skipped: $skipped');
  print('  Output directory: ${outDir.path}');

  // ── 9. Filter sounds by property ──────────────────────────────────────────

  print('\n=== Filter examples ===');

  final streams = sf.getActiveSounds().where((r) => r.isStream).toList();
  print('  Stream entries: ${streams.length}');

  final stereo = sf.getActiveSounds().where((r) => r.channels == 2).toList();
  print('  Stereo entries: ${stereo.length}');

  final highRate = sf
      .getActiveSounds()
      .where((r) => r.sampleRate >= 44100)
      .toList();
  print('  44100 Hz+:      ${highRate.length}');

  final bank2 = sf.getAllSounds().where((r) => r.bankIndex == 1).toList();
  print('  Bank 2 entries: ${bank2.length}');
}
