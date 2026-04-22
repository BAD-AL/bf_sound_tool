import 'dart:typed_data';
import 'bank_parser.dart';
import 'sound_record.dart';
import 'ucf_chunk.dart';
import 'ucf_writer.dart';

class SoundReplacer {
  static const int _searchStartTag = 0x23a0d95c;
  static const int _blockSize = 2048;

  /// Replace the audio for [record] with [newAudio] and return new file bytes.
  ///
  /// [newAudio] must be in the same raw format that [extractRawAudio] would
  /// return for this entry on this platform:
  ///   - PSP stream  → complete RIFF/WAV (ATRAC3+)
  ///   - PSP/PS2     → raw VAG ADPCM blocks (no header)
  ///   - Xbox        → raw Xbox ADPCM blocks (no WAV header)
  ///   - PC sample   → raw PCM16 bytes (no WAV header)
  ///   - PC stream   → raw Xbox ADPCM blocks (no WAV header)
  static Uint8List replace(
    Uint8List fileBytes,
    UcfChunk root,
    List<SoundBank> banks,
    SoundRecord record,
    Uint8List newAudio,
    String platform, {
    int? newSampleRate,
  }) {
    final bank = banks[record.bankIndex];

    final newInfoBody = _patchInfoChunk(
        fileBytes, bank, record, newAudio.length, platform,
        newSampleRate: newSampleRate);
    final newDataBody = _buildDataChunk(
        fileBytes, bank, record, newAudio, platform);

    return UcfWriter.serialize(root, fileBytes, {
      bank.infoChunk.offset: newInfoBody,
      bank.dataChunk.offset: newDataBody,
    });
  }

  /// Replace audio for multiple entries across any number of banks in a single
  /// serialization pass. [replacements] maps each SoundRecord to its new raw
  /// audio bytes. [newSampleRate] is applied uniformly to all replaced entries.
  static Uint8List replaceMany(
    Uint8List fileBytes,
    UcfChunk root,
    List<SoundBank> banks,
    Map<SoundRecord, Uint8List> replacements,
    String platform, {
    int? newSampleRate,
  }) {
    // Group replacements by bankIndex.
    final byBank = <int, Map<SoundRecord, Uint8List>>{};
    for (final entry in replacements.entries) {
      byBank.putIfAbsent(entry.key.bankIndex, () => {})[entry.key] = entry.value;
    }

    final chunkReplacements = <int, Uint8List>{};
    for (final bankIdx in byBank.keys) {
      final bank = banks[bankIdx];
      final bankReps = byBank[bankIdx]!;

      final newInfoBody = _patchInfoChunkMany(
          fileBytes, bank, bankReps, platform,
          newSampleRate: newSampleRate);
      final newDataBody = _buildDataChunkMany(
          fileBytes, bank, bankReps, platform);

      chunkReplacements[bank.infoChunk.offset] = newInfoBody;
      chunkReplacements[bank.dataChunk.offset] = newDataBody;
    }

    return UcfWriter.serialize(root, fileBytes, chunkReplacements);
  }

  // ── Multi-entry info/data helpers ────────────────────────────────────────

  static Uint8List _patchInfoChunkMany(
    Uint8List fileBytes,
    SoundBank bank,
    Map<SoundRecord, Uint8List> replacements,
    String platform, {
    int? newSampleRate,
  }) {
    final body = Uint8List.fromList(Uint8List.sublistView(
        fileBytes, bank.infoChunk.bodyOffset,
        bank.infoChunk.bodyOffset + bank.infoChunk.size));

    final positions = _findSearchStarts(fileBytes, bank.infoChunk);

    // Build audioOffset → (newSize, targetIdx) lookup.
    final repByOffset = <int, (Uint8List, int)>{};
    for (int i = 0; i < bank.entries.length; i++) {
      final e = bank.entries[i];
      for (final rep in replacements.entries) {
        if (rep.key.audioOffset == e.audioOffset) {
          repByOffset[e.audioOffset] = (rep.value, i);
          break;
        }
      }
    }

    int totalSize = 0;
    for (int i = 0; i < bank.entries.length; i++) {
      final e = bank.entries[i];
      if (e.skip) continue;
      final rep = repByOffset[e.audioOffset];
      if (rep != null) {
        final newDataSize = rep.$1.length;
        final newBlockPad = _calcBlockPad(newDataSize, bank.isStream, platform,
            bank.substreamInterleave);
        totalSize += newDataSize + newBlockPad;
        final ePos = positions[i + 1] - bank.infoChunk.bodyOffset;
        _patchUint32(body, ePos + 4,    newDataSize);
        _patchUint32(body, ePos + 0x14, newBlockPad);
        if (newSampleRate != null) {
          _patchUint32(body, ePos - 4, newSampleRate);
        }
      } else {
        totalSize += e.dataSize + e.blockPadding;
      }
    }

    _patchUint32(body, positions[0] - bank.infoChunk.bodyOffset + 4, totalSize);
    return body;
  }

  static Uint8List _buildDataChunkMany(
    Uint8List fileBytes,
    SoundBank bank,
    Map<SoundRecord, Uint8List> replacements,
    String platform,
  ) {
    final repByOffset = <int, Uint8List>{};
    for (final rep in replacements.entries) {
      repByOffset[rep.key.audioOffset] = rep.value;
    }

    final out = BytesBuilder(copy: false);
    for (final e in bank.entries) {
      if (e.skip) continue;
      final newAudio = repByOffset[e.audioOffset];
      if (newAudio != null) {
        final pad = _calcBlockPad(newAudio.length, bank.isStream, platform,
            bank.substreamInterleave);
        out.add(newAudio);
        if (pad > 0) out.add(Uint8List(pad));
      } else {
        out.add(Uint8List.sublistView(
            fileBytes, e.audioOffset, e.audioOffset + e.dataSize));
        if (e.blockPadding > 0) out.add(Uint8List(e.blockPadding));
      }
    }
    return out.toBytes();
  }

  // ── Info chunk patching ───────────────────────────────────────────────────

  static Uint8List _patchInfoChunk(
    Uint8List fileBytes,
    SoundBank bank,
    SoundRecord target,
    int newDataSize,
    String platform, {
    int? newSampleRate,
  }) {
    // Copy info chunk body then patch three fields in-place.
    final body = Uint8List.fromList(Uint8List.sublistView(
        fileBytes, bank.infoChunk.bodyOffset,
        bank.infoChunk.bodyOffset + bank.infoChunk.size));

    final positions = _findSearchStarts(fileBytes, bank.infoChunk);
    // positions[0] = bank-level, positions[1..n] = per-entry (matches bank.entries order)

    // Find target entry index.
    int targetIdx = -1;
    for (int i = 0; i < bank.entries.length; i++) {
      if (bank.entries[i].audioOffset == target.audioOffset) {
        targetIdx = i;
        break;
      }
    }
    assert(targetIdx >= 0, 'Target entry not found in bank');

    final newBlockPad = _calcBlockPad(newDataSize, bank.isStream, platform,
        bank.substreamInterleave);

    // Recalculate total data chunk size.
    int totalSize = 0;
    for (int i = 0; i < bank.entries.length; i++) {
      final e = bank.entries[i];
      if (e.skip) continue;
      if (i == targetIdx) {
        totalSize += newDataSize + newBlockPad;
      } else {
        totalSize += e.dataSize + e.blockPadding;
      }
    }

    // Patch bank-level total (at positions[0] + 4, relative to chunk body start).
    _patchUint32(body, positions[0] - bank.infoChunk.bodyOffset + 4, totalSize);

    // Patch target entry dataSize, blockPadding, and optionally sampleRate.
    final ePos = positions[targetIdx + 1] - bank.infoChunk.bodyOffset;
    _patchUint32(body, ePos + 4,    newDataSize);
    _patchUint32(body, ePos + 0x14, newBlockPad);
    if (newSampleRate != null) {
      _patchUint32(body, ePos - 4, newSampleRate);
    }

    return body;
  }

  // ── Data chunk rebuild ────────────────────────────────────────────────────

  static Uint8List _buildDataChunk(
    Uint8List fileBytes,
    SoundBank bank,
    SoundRecord target,
    Uint8List newAudio,
    String platform,
  ) {
    final out = BytesBuilder(copy: false);

    for (int i = 0; i < bank.entries.length; i++) {
      final e = bank.entries[i];
      if (e.skip) continue;

      final bool isTarget = e.audioOffset == target.audioOffset;
      final Uint8List audio = isTarget
          ? newAudio
          : Uint8List.sublistView(
              fileBytes, e.audioOffset, e.audioOffset + e.dataSize);

      final int pad = isTarget
          ? _calcBlockPad(newAudio.length, bank.isStream, platform,
              bank.substreamInterleave)
          : e.blockPadding;

      out.add(audio);
      if (pad > 0) out.add(Uint8List(pad));
    }

    return out.toBytes();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static List<int> _findSearchStarts(Uint8List fileBytes, UcfChunk infoChunk) {
    final positions = <int>[];
    final end = infoChunk.bodyOffset + infoChunk.size;
    for (int pos = infoChunk.bodyOffset; pos + 8 <= end; pos += 4) {
      if (_peekUint32(fileBytes, pos) == _searchStartTag) positions.add(pos);
    }
    return positions;
  }

  static int _calcBlockPad(
      int dataSize, bool isStream, String platform, int substreamInterleave) {
    if (!isStream) return 0;
    if (platform == 'psp') {
      final rem = dataSize % _blockSize;
      return rem == 0 ? 0 : _blockSize - rem;
    }
    // Xbox/PS2 streams: align each entry to substreamInterleave boundary.
    if (substreamInterleave <= 0) return 0;
    final rem = dataSize % substreamInterleave;
    return rem == 0 ? 0 : substreamInterleave - rem;
  }

  static int _peekUint32(Uint8List bytes, int offset) =>
      (bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24)) &
      0xFFFFFFFF;

  static void _patchUint32(Uint8List bytes, int offset, int value) {
    bytes[offset]     = value & 0xFF;
    bytes[offset + 1] = (value >> 8) & 0xFF;
    bytes[offset + 2] = (value >> 16) & 0xFF;
    bytes[offset + 3] = (value >> 24) & 0xFF;
  }
}
