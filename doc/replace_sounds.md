# replace_sounds

Replaces sound entries in a Battlefront I/II `.lvl` file using WAV files from a folder.
Supports PC, Xbox, PS2, and PSP platforms. No external tools required for PC, Xbox,
PS2, and PSP sample banks. PSP stream entries require an ATRAC3+ WAV pre-encoded with
`at3tool` (see [PSP streams](#psp-streams-atrac3) below).

---

## Quick start

```
dart run bin/replace_sounds.dart -i ingame.lvl -r my_sounds/
```

Place `.wav` files named after the sound entries you want to replace in `my_sounds/`,
run the command, and a patched sound `.lvl` is produced.

---

## Requirements

- WAV files named exactly after the target sound entry (e.g. `explosion_large.wav`)
- **Sample entries:** mono or stereo input — stereo is automatically mixed to mono
- **Stream entries:** mono or stereo input — stereo is preserved when the stream entry
  is itself stereo; a mono WAV replacing a stereo stream has its channel duplicated
- Supported WAV formats: PCM 16-bit, PCM 24-bit, PCM 32-bit, IEEE float 32-bit
- PSP stream entries only: supply an ATRAC3+ WAV produced by `at3tool` (any WAV format
  is accepted for passthrough — PCM is not required)

---

## Options

| Flag | Default | Description |
|---|---|---|
| `-i <file>` | — | Input `.lvl` file **[required]** |
| `-r <folder>` | — | Folder containing replacement `.wav` files **[required]** |
| `-p xbox\|ps2\|psp\|pc` | `pc` | Platform of the input file |
| `-v bf1\|bf2` | `bf2` | Game version |
| `-o <file>` | `<input>_replaced.lvl` | Output file path |
| `--rate <hz>` | — | Resample all replacements to this rate |
| `--log-only` | — | Preview the replacement plan without writing any files |
| `-h`, `--help` | — | Show usage |

---

## Naming your WAV files

Each WAV file must be named after the **exact sound entry name** in the `.lvl` file,
with a `.wav` extension:

```
my_sounds/
  explosion_large.wav
  gun_blaster_fire.wav
  trooper_pain01.wav
```

Entry names are case-sensitive. Use `bf_sound_tool --list` (or `--verify`) on the
original file to see the exact names if you are unsure.

### Aliases

Some entries in a `.lvl` file are **aliases** — they contain no audio data of their
own and are skipped automatically. The tool will tell you if a WAV filename matched
an alias:

```
rep_blaster_fire   SKIP (alias — no audio data stored in this file)
```

The BF2 format does not record which entry an alias points to, so the tool cannot
suggest an alternative name. Use `bf_sound_tool --list` to identify the real entry
that holds the audio data you want to replace.

---

## Sample rate handling

By default the tool uses **whatever sample rate your WAV file has** — no resampling
is performed. This is the safest choice; the game reads the rate from the file header
and plays back accordingly.

Rate overrides apply to sample entries and stream entries alike. PSP stream passthrough
is unaffected — the at3plus file's internal rate is used regardless of any override.

### Global override: `--rate`

Resamples every replacement to the same rate:

```
dart run bin/replace_sounds.dart -i ingame.lvl -r my_sounds/ --rate 22050
```

### Per-entry override: `rates.txt`

Place a `rates.txt` file in your replacements folder. Each line is `name: rate`.
Lines beginning with `#` are comments and are ignored.

```
# rates.txt
explosion_large: 22050
gun_blaster_fire: 11025
# everything else keeps its WAV native rate
```

**Priority order:** `rates.txt` entry → `--rate` global → WAV native rate (no resample)

### Why downsample?

Game sound memory is limited on all platforms. Cutting a sound from 44100 Hz to
22050 Hz halves its memory footprint with minimal perceived quality loss for most
effects. Ambient loops and music benefit from keeping a higher rate; short one-shot
effects can often go to 11025 Hz without noticeable degradation.

---

## Platform notes

### PC (`-p pc`)
The most common modding target. PC sample banks store raw PCM16 — no encoding step
is involved. Any valid PCM WAV drops in cleanly.

PC stream banks use Xbox IMA ADPCM (same format as Xbox streams).

### Xbox (`-p xbox`)
All audio — samples and streams — is stored as Xbox IMA ADPCM. The tool encodes your
WAV to ADPCM automatically. Due to the block-based nature of ADPCM (65 samples per
36-byte block), the output size rounds up to the nearest block boundary — this is
normal.

### PS2 (`-p ps2`)
Sample banks use VAG ADPCM. The tool encodes your WAV to VAG automatically. Output
rounds up to the nearest 16-byte VAG block — this is normal.

PS2 stream banks are also VAG-encoded. Stereo streams store L and R as independent
mono VAG substreams interleaved at 16 384-byte chunk boundaries. The tool handles
this automatically when you supply a stereo WAV for a stereo stream entry.

### PSP (`-p psp`)
PSP sample banks use VAG ADPCM, handled identically to PS2 samples.

PSP has tighter memory limits than other platforms — downsampling to 11025 Hz is
often necessary to keep the total bank size within the game's budget.

PSP stream banks use ATRAC3+ — see [PSP streams](#psp-streams-atrac3) below.

---

## Streams

All four platforms support stream replacement. The encoding format depends on platform:

| Platform | Stream format | Stereo |
|---|---|---|
| PC | Xbox IMA ADPCM (block-interleaved L/R) | yes |
| Xbox | Xbox IMA ADPCM (block-interleaved L/R) | yes |
| PS2 | VAG ADPCM (L/R substreams at 16 384-byte boundaries) | yes |
| PSP | ATRAC3+ WAV passthrough | yes (from source file) |

**Stereo preservation:** when a stream entry in the `.lvl` is stereo and your
replacement WAV is also stereo, both channels are encoded and the stereo image is
preserved. A mono WAV replacing a stereo stream entry has its single channel
duplicated to fill both outputs.

### PSP streams (ATRAC3+)

PSP streams are stored in the `.lvl` as complete RIFF/WAV files using the ATRAC3+
subformat. This tool cannot synthesize ATRAC3+ natively, so you must encode your
audio with Sony's `at3tool` first:

```
at3tool -e -br 132 my_sound.wav my_sound_at3.wav
```

Then name the resulting file after the stream entry (keep the `.wav` extension) and
place it in your replacements folder:

```
my_sounds/
  hot_amb_wind.wav    ← output of at3tool, not a PCM WAV
```

The tool reads the sample rate from the file header and passes the bytes through
unchanged — no re-encoding happens.

---

## Previewing changes with `--log-only`

Run with `--log-only` to see exactly what will happen before writing anything:

```
dart run bin/replace_sounds.dart -i ingame.lvl -r my_sounds/ --log-only
```

Example output:

```
Parsing ingame.lvl as pc (bf2)...
  312 entries (298 active, 14 aliases)
Loaded 2 rate override(s) from rates.txt

Replacement plan:
Name                                        SrcRate   DstRate   Status
--------------------------------------------------------------------------
explosion_large                             44100     22050     OK (resample)
gun_blaster_fire                            22050     11025     OK (resample)
trooper_pain01                              22050     22050     OK
hot_amb_wind                                44100     44100     OK stereo
rep_blaster_fire                                                SKIP (alias — no audio data stored in this file)
missing_sound                                                   SKIP (not found in lvl)

  Skipped: 1 alias(es), 1 unknown name(s)
  Replacing: 4 entries
```

For PSP stream entries the status shows `OK (at3plus passthrough)` instead.

Nothing is written until you remove `--log-only`.

---

## Worked examples

### Replace a handful of sounds in a PC map

```
dart run bin/replace_sounds.dart \
  -i "geo/pc/nab.lvl" \
  -r sounds/nab_replacements/ \
  -p pc
```

### Replace with a forced downsample

```
dart run bin/replace_sounds.dart \
  -i "geo/pc/nab.lvl" \
  -r sounds/nab_replacements/ \
  -p pc \
  --rate 22050
```

### Per-entry rates via sidecar, writing to a specific output path

```
# sounds/nab_replacements/rates.txt
explosion_large: 22050
amb_wind_loop: 44100

dart run bin/replace_sounds.dart \
  -i "geo/pc/nab.lvl" \
  -r sounds/nab_replacements/ \
  -p pc \
  -o "geo/pc/nab_mod.lvl"
```

### Replace a stereo ambient stream (PC or Xbox)

Supply a stereo WAV named after the stream entry. The tool encodes both channels as
Xbox IMA ADPCM and writes the interleaved stereo stream automatically.

```
dart run bin/replace_sounds.dart \
  -i "geo/xbox/hot.lvl" \
  -r sounds/hot_replacements/ \
  -p xbox
```

### Replace samples in a PSP map

```
dart run bin/replace_sounds.dart \
  -i "geo/psp/nab.lvl" \
  -r sounds/nab_replacements/ \
  -p psp \
  --rate 11025
```

PSP has tighter memory limits — downsampling to 11025 Hz is often necessary to keep
the total bank size within the game's budget.

### Replace a PSP stream

Encode your audio to ATRAC3+ first, then drop it in the replacements folder:

```
# Step 1 — encode with at3tool
at3tool -e -br 132 my_ambient.wav hot_amb_wind.wav

# Step 2 — replace
dart run bin/replace_sounds.dart \
  -i "geo/psp/hot.lvl" \
  -r sounds/hot_replacements/ \
  -p psp
```

### Preview a PS2 replacement batch

```
dart run bin/replace_sounds.dart \
  -i "geo/ps2/nab.lvl" \
  -r sounds/nab_replacements/ \
  -p ps2 \
  --log-only
```

---

## Troubleshooting

**"not found in lvl"** — The filename (without `.wav`) does not match any entry name.
Use `bf_sound_tool --list` on the original file to confirm the exact name. Names are
case-sensitive.

**"alias — no audio data stored in this file"** — You named a WAV after an alias
entry. Use `bf_sound_tool --list` to identify the real entry that holds the audio.

**"Unsupported WAV format 0x..."** — This error applies to sample entries only. The
tool only accepts uncompressed PCM and IEEE float WAVs for encoding. Re-export from
your DAW as "PCM 16-bit" or "PCM 24-bit" WAV. MP3, AAC, and other compressed formats
are not accepted. (PSP stream entries are exempt — any RIFF/WAV format is accepted
for passthrough.)

**Output sounds wrong pitch or distorted (Xbox/PS2/PSP sample entries)** — Verify
the replacement WAV was exported as mono. Stereo input is mixed to mono automatically
for sample entries, but some recording software produces unexpected results with
surround or dual-mono layouts. For Xbox, also check that the WAV sample rate is a
standard value (8000, 11025, 22050, 44100 Hz); unusual rates can cause IMA ADPCM
encoder drift.

**Stereo stream sounds mono or has wrong channel content** — Verify your WAV is
genuinely stereo (two distinct channels) and that the stream entry in the `.lvl` is
also stereo. Use `bf_sound_tool --list` to check the entry's channel count. A mono
stream entry will always be replaced with a mono encoding regardless of the input.

**File size grew unexpectedly** — This is normal if you replaced short sounds with
longer ones, or swapped highly downsampled originals with higher-rate audio. The tool
rewrites only the affected data chunks; all other banks are untouched.

**PSP sample sounds do not play in-game after replacement** — PSP sound banks have a
fixed memory budget. If the total bank size after replacement exceeds that budget the
game may silently drop the bank. Re-run with `--rate 11025` (or use `rates.txt` to
target specific entries) to reduce bank size.

**PSP stream sounds wrong after replacement** — The at3tool output must match the
channel count and approximate duration expected by the game. Using a very different
bitrate (`-br` value) from the original may cause playback issues on hardware. Check
the original entry's properties with `bf_sound_tool --list` and match them where
possible.
