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

  /// Bank-level format identifier (tag 0xb99d8552).
  /// Known values: 2 (PCM16 on Xbox), 4/5 (ADPCM on Xbox/PC), 6 (PSP/PS2).
  final int format;

  /// Substream count (tag 0x7aaf1a1c). 1 for normal, 2 for interleaved ambient.
  final int numSubStreams;

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
    required this.format,
    required this.numSubStreams,
    required this.substreamInterleave,
  });

  /// A bank is a stream if it has multiple substreams (ambient) OR 
  /// if it is on PC/Xbox and has the SubStreamInterleave tag (even if value is small).
  /// More reliably: if it's not a sample bank (.bnk).
  /// Practically: if numSubStreams > 0 and substreamInterleave > 0.
  bool get isStream => numSubStreams > 0 && substreamInterleave > 0;
}

class BankParser {
  static const int _tagFormat = 0xb99d8552;
  static const int _tagChannels = 0x7816084b;
  static const int _tagSegments = 0x40fbdebd;
  static const int _tagSize = 0x23a0d95c; // fnvHash("size")
  static const int _tagSubStreams = 0x7aaf1a1c;
  static const int _tagInterleave = 0x740fdb0c;
  static const int _tagPadding = 0x809608b6;
  static const int _aliasTag = 0x7D268157; // fnvHash("alias")
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

    // Find all size tags within the info chunk body.
    final end = infoChunk.bodyOffset + infoChunk.size;
    final positions = <int>[];
    for (int pos = infoChunk.bodyOffset; pos + 8 <= end; pos += 4) {
      if (r.peekUint32(pos) == _tagSize) {
        positions.add(pos);
      }
    }

    if (positions.isEmpty) {
      throw FormatException('No size tags found in bank info chunk');
    }

    // Parse bank header by scanning for tags before the first size tag.
    int format = 0;
    int channels = 1; // default to mono for sample banks
    int wavCount = 0;
    int numSubStreams = 0;
    int substreamInterleave = 0;

    final firstSizePos = positions[0];
    for (int p = infoChunk.bodyOffset; p + 8 <= firstSizePos + 32; p += 4) {
      final tag = r.peekUint32(p);
      final val = r.peekUint32(p + 4);
      switch (tag) {
        case _tagFormat:
          format = val;
        case _tagChannels:
          channels = val;
        case _tagSegments:
          wavCount = val;
        case _tagSubStreams:
          numSubStreams = val;
        case _tagInterleave:
          substreamInterleave = val;
      }
    }

    // Special case: some sample banks (like ARE.lvl Bank 2) have wavCount
    // at a different tag (0x98b889ce) or just before size.
    // If wavCount is 0, try to find it.
    if (wavCount == 0) {
      final unkTag = r.peekUint32(firstSizePos - 8);
      if (unkTag == 0x98b889ce || unkTag == _tagSegments) {
        wavCount = r.peekUint32(firstSizePos - 4);
      }
    }

    final isStream = numSubStreams > 0 && substreamInterleave > 0;

    // Parse sound entries from the remaining size tags.
    final entries = <SoundEntry>[];
    int readPos = dataChunk.bodyOffset;

    // Entry records start AFTER the bank data descriptor.
    // Usually the bank descriptor has its own size tag at positions[0].
    for (int idx = 1; idx < positions.length; idx++) {
      final i = positions[idx];

      final nameHash = r.peekUint32(i - 12);
      final sampleRate = r.peekUint32(i - 4);
      final dataSize = r.peekUint32(i + 4);
      final blockPadding = r.peekUint32(i + 0x14);
      final skipCheck1 = r.peekUint32(i + 0x18);
      final skipCheck2 = r.peekUint32(i + 0x1c);

      // When skip=true, skipCheck2 (i+0x1c) holds the alias target hash on
      // console platforms. On PC, skip fires when skipCheck2==0, so no hash.
      final skip = _shouldSkip(skipCheck1, skipCheck2, platform);
      String? aliasFor;
      if (skip && skipCheck2 != 0) {
        aliasFor = dict.resolve(skipCheck2);
      }

      // 2048-byte aligned read size for streams.
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
      format: format,
      numSubStreams: numSubStreams,
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
