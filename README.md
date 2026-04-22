# Battlefront Sound Tool

A pure-Dart library for parsing, extracting, and modifying sound files (`.lvl`, `.bnk`, `.str`) from *Star Wars Battlefront* (2004) and *Star Wars Battlefront II* (2005).

Designed with web compatibility in mind, this library enables the creation of browser-based modding tools without requiring native external binaries like `ffmpeg` for core tasks.

## Key Features

- **Multi-Platform Support:** Full handling for Xbox, PC, PS2, and PSP sound formats.
- **Pure Dart Implementation:** Web-ready, no native dependencies. Includes built-in encoders for VAG (PS2/PSP) and Xbox ADPCM.
- **The Architect (Structure):** Surgical modification of UCF/LVL containers, rebuilding data chunks and patching metadata tags with precision.
- **The Translator (Audio):** High-level API for standard WAV files, including automatic resampling, mono/stereo handling, and platform-specific encoding.
- **Batch Processing:** Replace hundreds of sounds in a single serialization pass.
- **Self-Describing Metadata:** Dynamically parses bank headers and entry tags to handle game-specific quirks (like Xbox PCM16 sample banks).

## Library reference

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  bf_sound_tool:
    git: https://github.com/BAD-AL/bf_sound_tool.git
```

## Library Usage

### 1. Parsing and Metadata
```dart
import 'package:bf_sound_tool/bf_sound_tool.dart';

final bytes = File('shell.lvl').readAsBytesSync();
final sf = BattlefrontSoundFile(bytes, 'psp', 'bf2');

for (final record in sf.getActiveSounds()) {
  print('Sound: ${record.name} | Rate: ${record.sampleRate}Hz | Type: ${record.typeLabel}');
}
```

### 2. Replacing Sounds with WAVs
```dart
final wavBytes = File('my_new_sound.wav').readAsBytesSync();
final record = sf.getSound('saberon')!;

// Automatically resamples and encodes to the correct platform format
final newLvlBytes = sf.replaceWithWav(record, wavBytes);
File('shell_modded.lvl').writeAsBytesSync(newLvlBytes);
```

### 3. Batch Replacement
```dart
final replacements = {
  sf.getSound('saberon')!: File('new_on.wav').readAsBytesSync(),
  sf.getSound('saberoff')!: File('new_off.wav').readAsBytesSync(),
};

final newLvlBytes = sf.replaceManyWithWav(replacements);
```

## CLI Tools

The project includes two primary command-line tools:

### `bf_sound_tool`
The general-purpose Swiss Army knife for sound files.
- **Extract:** `dart bin/bf_sound_tool.dart -i sound.lvl -p psp --extract`
- **Verify:** `dart bin/bf_sound_tool.dart -i sound.lvl -p xbox --verify`
- **List:** `dart bin/bf_sound_tool.dart -i sound.lvl -p pc --list`

### `replace_sounds`
An optimized tool for bulk-replacing sounds using a folder of WAV files.
- Matches filenames automatically (e.g., `saberon.wav` -> `saberon` entry).
- Handles batch resampling and encoding in one pass.
- Supports `rates.txt` sidecar for per-entry sample rate overrides.
- `dart bin/replace_sounds.dart -i shell.lvl -r ./my_wavs/ -p psp`

## Technical Reference

For a deep dive into the underlying UCF container and bank formats, see [Battlefront Sound file analysis](https://github.com/BAD-AL/SWBF2_Xbox_mod_effort/wiki/Sound-File-Analysis).

## Credits

Developed for the Battlefront modding community. Special thanks to the creators of the original VB ripper and the documentation efforts of the community over the last 20 years.
