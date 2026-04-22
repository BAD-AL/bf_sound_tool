import 'dart:typed_data';
import 'byte_reader.dart';
import 'dictionary.dart';
import 'ucf_chunk.dart';
import 'ucf_parser.dart';

class SoundEntry {
  final int nameHash;
  final String name;
  final int sampleRate;
  final int dataSize;      // raw from info chunk
  final int audioOffset;   // absolute file offset of audio data start
  final int audioReadSize; // bytes to read (padded to block boundary for streams)
  final int blockPadding;  // bytes between end of audio and next entry (from info chunk)
  final bool skip;

  /// Resolved name of the aliased entry, or null if this is not an alias.
  final String? aliasFor;

  const SoundEntry({
    required this.nameHash,
    required this.name,
    required this.sampleRate,
    required this.dataSize,
    required this.audioOffset,
    required this.audioReadSize,
    required this.blockPadding,
    required this.skip,
    this.aliasFor,
  });
}

class SoundBank {
  final int wavCount;
  final int channels;
  final List<SoundEntry> entries;
  final UcfChunk infoChunk;
  final UcfChunk dataChunk;

  /// Substream interleave block size in bytes (tag "SubStreamInterleave").
  /// Xbox streams: 36864 (0x9000).  PS2 streams: 16384 (0x4000).
  /// Sample banks: 0 (field absent or irrelevant).
  final int substreamInterleave;

  const SoundBank({
    required this.wavCount,
    required this.channels,
    required this.entries,
    required this.infoChunk,
    required this.dataChunk,
    required this.substreamInterleave,
  });

  bool get isStream => channels <= 2;
}

class BankParser {
  static const int _searchStartTag = 0x23a0d95c; // fnvHash("size")
  static const int _aliasTag = 0x7D268157; // fnvHash("alias") — console alias entry marker
  static const int _blockSize = 2048;

  /// Walk the UCF tree and parse all (info, data) bank pairs.
  static List<SoundBank> parseBanks(
    UcfChunk root,
    Uint8List fileBytes,
    Dictionary dict, {
    required String platform,
  }) {
    final banks = <SoundBank>[];
    for (final chunk in root.allChunks()) {
      if (!chunk.hasChildren) continue;
      final info = _childById(chunk, UcfParser.idInfo);
      final data = _childById(chunk, UcfParser.idData);
      if (info != null && data != null) {
        banks.add(_parseBank(fileBytes, info, data, dict, platform));
      }
    }
    return banks;
  }

  static UcfChunk? _childById(UcfChunk parent, int id) {
    for (final child in parent.children) {
      if (child.id == id) return child;
    }
    return null;
  }

  static SoundBank _parseBank(
    Uint8List fileBytes,
    UcfChunk infoChunk,
    UcfChunk dataChunk,
    Dictionary dict,
    String platform,
  ) {
    final r = ByteReader(fileBytes);

    // Find all SearchStart tag positions within the info chunk body.
    // Pairs are 8-byte aligned, so scan every 4 bytes.
    final end = infoChunk.bodyOffset + infoChunk.size;
    final positions = <int>[];
    for (int pos = infoChunk.bodyOffset; pos + 8 <= end; pos += 4) {
      if (r.peekUint32(pos) == _searchStartTag) {
        positions.add(pos);
      }
    }

    // First SearchStart = bank-level data descriptor.
    //   bankI - 4  : wavCount (last field of bank header)
    //   bankI - 20 : channel count (uint16 in bank header)
    //   bankI + 12 : substream count value  (tag 0x7aaf1a1c at bankI+8)
    //   bankI + 20 : substream interleave value (tag 0x740fdb0c at bankI+16)
    final bankI = positions[0];
    final wavCount = r.peekUint32(bankI - 4);
    r.seek(bankI - 20);
    final channels = r.readUint16();
    final substreamInterleave = r.peekUint32(bankI + 20);

    final isStream = channels <= 2;

    // Parse sound entries from the remaining SearchStarts.
    final entries = <SoundEntry>[];
    int readPos = dataChunk.bodyOffset; // tracks position within data chunk body

    for (int idx = 1; idx < positions.length; idx++) {
      final i = positions[idx];

      final nameHash = r.peekUint32(i - 12);
      final sampleRate = r.peekUint32(i - 4);
      final dataSize = r.peekUint32(i + 4);
      final blockPadding = r.peekUint32(i + 0x14);
      final skipCheck1 = r.peekUint32(i + 0x18);
      final skipCheck2 = r.peekUint32(i + 0x1c);

      final skip = _shouldSkip(skipCheck1, skipCheck2, platform);

      // When skip=true, skipCheck2 (i+0x1c) holds the alias target hash on
      // console platforms. On PC, skip fires when skipCheck2==0, so no hash.
      String? aliasFor;
      if (skip && skipCheck2 != 0) {
        aliasFor = dict.resolve(skipCheck2);
      }

      // 2048-byte aligned read size for streams (matches VB output file sizes).
      // Sample banks use raw dataSize with no extra padding.
      int audioReadSize = dataSize;
      if (isStream && (readPos + dataSize) % _blockSize != 0) {
        audioReadSize =
            dataSize + (_blockSize - (readPos + dataSize) % _blockSize);
      }

      entries.add(SoundEntry(
        nameHash: nameHash,
        name: dict.resolve(nameHash),
        sampleRate: sampleRate,
        dataSize: dataSize,
        audioOffset: readPos,
        audioReadSize: audioReadSize,
        blockPadding: blockPadding,
        skip: skip,
        aliasFor: aliasFor,
      ));

      // Only advance readPos for entries whose audio lives in this file.
      // Skipped entries reference audio in an external bank (e.g. PS2 common
      // bank) and occupy no space in this data chunk.
      // Stream banks: stride = dataSize + blockPadding (interleave-aligned).
      // Sample banks: blockPadding is 0, so stride = dataSize.
      if (!skip) {
        readPos += isStream ? dataSize + blockPadding : audioReadSize;
      }
    }

    return SoundBank(
      wavCount: wavCount,
      channels: channels,
      entries: entries,
      infoChunk: infoChunk,
      dataChunk: dataChunk,
      substreamInterleave: substreamInterleave,
    );
  }

  static bool _shouldSkip(int skipCheck1, int skipCheck2, String platform) {
    if (platform != 'pc') {
      return skipCheck1 == _aliasTag;
    }
    // PC logic: skip if skipCheck2 == 0 (except global.lvl; common.bnk checks skipCheck1)
    return skipCheck2 == 0;
  }
}
