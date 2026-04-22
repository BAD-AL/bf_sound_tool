# bf_sound_tool API Reference

A Dart library for parsing and extracting audio from *Star Wars Battlefront* (2004)
and *Star Wars Battlefront II* (2005) sound `.lvl`, `.bnk`, and `.str` files.

Supports Xbox, PC, and PS2 platforms. Works as a CLI tool, a Dart library,
or a Flutter / web package.

---

## Quick Start

```dart
import 'dart:io';
import 'package:bf_sound_tool/bf_sound_tool.dart';

// 1. Load the dictionary (optional — unresolved hashes fall back to hex strings)
final dict = Dictionary();
await dict.loadFile('path/to/dictionary.txt');

// 2. Parse the file
final bytes = File('hot.lvl').readAsBytesSync();
final sf = BattlefrontSoundFile(bytes, 'xbox', 'bf2', dictionary: dict);

// 3. Extract a specific sound by name
final wav = sf.extractWavByName('hot_amb_wind');
File('hot_amb_wind.wav').writeAsBytesSync(wav);
```

---

## BattlefrontSoundFile

```dart
BattlefrontSoundFile(
  Uint8List bytes,
  String platform,       // 'xbox' | 'pc' | 'ps2'
  String version,        // 'bf2' | 'bf1'
  {Dictionary? dictionary}
)
```

Parses the file on construction. Holds the source bytes internally for
on-demand extraction. The `dictionary` parameter is optional; without it,
sound names that cannot be resolved appear as `0x<hash>`.

### Querying sounds

| Method | Returns | Description |
|--------|---------|-------------|
| `getAllSounds()` | `List<SoundRecord>` | Every entry, including `skip=true` entries |
| `getActiveSounds()` | `List<SoundRecord>` | Only entries where `skip` is false |
| `getSound(String name)` | `SoundRecord?` | First entry matching `name`, or `null` |

```dart
// Iterate all active sounds
for (final r in sf.getActiveSounds()) {
  print('${r.name}  ${r.sampleRate} Hz  ${r.channelLabel}  ${r.formattedOffset}');
}

// Look up a single sound (returns null if not found)
final record = sf.getSound('saberon');
if (record != null) {
  print(record); // SoundRecord(saberon, rate=22050, ch=1, offset=0x2aeb008, ...)
}
```

### Extracting audio — by SoundRecord

Use these when you already have a `SoundRecord` (e.g. from iterating `getActiveSounds()`).
The record lookup happens once; subsequent calls to extract are O(1).

| Method | Returns | Description |
|--------|---------|-------------|
| `extractRawAudio(record)` | `Uint8List` | Raw encoded bytes (no WAV header) |
| `extractWav(record)` | `Uint8List` | WAV-wrapped audio |
| `extractAmbWavs(record)` | `(Uint8List front, Uint8List back)` | Deinterleaved front + back WAVs for PC/PS2 stereo ambient streams |

```dart
final record = sf.getSound('hot_amb_wind')!;

// WAV file ready to write to disk or feed to an audio player
final wav = sf.extractWav(record);

// Raw bytes only (no header) — useful if you supply your own container
final raw = sf.extractRawAudio(record);

// PC/PS2 4-channel ambient streams → two stereo WAVs
if (record.name.contains('_amb_') && record.channels == 2) {
  final (front, back) = sf.extractAmbWavs(record);
  File('${record.name}_fnt.wav').writeAsBytesSync(front);
  File('${record.name}_bck.wav').writeAsBytesSync(back);
}
```

### Extracting audio — by name (convenience overloads)

Use these when you know a sound is present and don't need the `SoundRecord`.
Each call performs an O(n) name scan. Throw `ArgumentError` if the name is
not found.

| Method | Returns |
|--------|---------|
| `extractRawAudioByName(String name)` | `Uint8List` |
| `extractWavByName(String name)` | `Uint8List` |
| `extractAmbWavsByName(String name)` | `(Uint8List front, Uint8List back)` |

```dart
// Fast one-liner when you know the name
final wav = sf.extractWavByName('saberon');
```

---

## SoundRecord

Immutable, pure-data description of a single sound entry. Contains no
reference to file bytes — safe to store in UI state, serialize, or pass
across isolate boundaries.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | Resolved sound name, or `0x<hash>` if unknown |
| `nameHash` | `int` | Raw FNV-1a hash of the sound name |
| `sampleRate` | `int` | Sample rate in Hz (e.g. 44100, 22050) |
| `channels` | `int` | Resolved channel count: always `1` for sample-bank entries, `bank.channels` for stream-bank entries |
| `isStream` | `bool` | `true` for stream banks (`.str`); `false` for sample banks (`.bnk`) |
| `skip` | `bool` | `true` if audio is stored in an external file (e.g. `common.bnk` on PC) |
| `dataSize` | `int` | Raw audio byte count from file metadata |
| `audioOffset` | `int` | Absolute byte offset of audio data in the source file |
| `audioReadSize` | `int` | Bytes to read for output (stream: 2048-aligned; samples: == `dataSize`) |
| `bankIndex` | `int` | Zero-based index of the bank this entry belongs to |

### Computed helpers

| Property | Type | Example |
|----------|------|---------|
| `formattedOffset` | `String` | `"0x2aeb008"` |
| `channelLabel` | `String` | `"stereo"` or `"mono"` |
| `typeLabel` | `String` | `"stream"` or `"sample"` |

---

## Dictionary

Maps FNV-1a hashes to human-readable sound names. Optional but strongly
recommended — without it, unresolved names appear as `0x<hash>`.

```dart
final dict = Dictionary();
await dict.loadFile('path/to/dictionary.txt');   // from file
// — or —
await dict.loadString(rawText);                  // from in-memory string

// Manual lookup
final name = dict.resolve(0x37386ae0);           // returns hex string if unknown
```

The bundled `dictionary.txt` (in `source_code/SoundRipperVB/`) covers the
majority of known BF1 and BF2 sound names.

---

## Platform notes

| Platform | Audio format | Notes |
|----------|-------------|-------|
| `xbox` | Xbox ADPCM (WAV format `0x0069`) | Most sound files tested against this platform |
| `pc` | IMA ADPCM (streams) / PCM16 (samples) | Many entries have `skip=true` (audio is in `common.bnk`) |
| `ps2` | VAG ADPCM | 16384-byte block alignment |

### PC ambient streams
PC and PS2 stereo ambient streams (`_amb_` entries, `channels == 2`) interleave
two stereo substreams (front/back channel pairs) into a single data blob.
Use `extractAmbWavs()` rather than `extractWav()` to obtain the two separate
stereo WAV files.

```dart
if (sf.platform != 'xbox' &&
    record.name.contains('_amb_') &&
    record.channels == 2) {
  final (front, back) = sf.extractAmbWavs(record);
}
```

---

## Lower-level building blocks

The following classes are also exported for advanced use:

| Class | Description |
|-------|-------------|
| `UcfParser` | Parses the UCF binary container (RIFF-like chunk tree) |
| `BankParser` | Walks the UCF tree and builds `SoundBank` / `SoundEntry` lists |
| `AudioExtractor` | Extracts raw bytes from file given a `SoundEntry` |
| `WavWriter` | Builds WAV headers for Xbox ADPCM and PCM16 |
| `AmbDeinterlacer` | Splits interleaved PC/PS2 ambient streams into front/back |
| `FnvHash` | FNV-1a hash used for all sound name lookups |
| `ByteReader` | Little-endian binary reader over a `Uint8List` |
