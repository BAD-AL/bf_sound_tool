/// Immutable, pure-data description of a single sound entry.
///
/// Contains no reference to file bytes — safe to store in UI state,
/// serialize, or pass across isolate boundaries.
class SoundRecord {
  final String name;
  final int nameHash;
  final int sampleRate;

  /// Resolved channel count: always 1 for sample-bank entries,
  /// bank.channels for stream-bank entries.
  final int channels;

  final bool isStream;
  final bool skip;

  /// Resolved name of the aliased entry, or null if this is not an alias.
  final String? aliasFor;

  /// Raw audio byte count stored in the file metadata.
  final int dataSize;

  /// Absolute byte offset of this entry's audio data within the source file.
  final int audioOffset;

  /// Bytes to read for output (stream banks: 2048-aligned; samples: == dataSize).
  final int audioReadSize;

  /// Zero-based index of the bank this entry belongs to.
  final int bankIndex;

  /// Stereo channel interleave block size in bytes (PS2: 16384, Xbox: 36864).
  /// Zero for sample banks or mono streams where interleaving does not apply.
  final int substreamInterleave;

  /// Bank-level format identifier (tag 0xb99d8552).
  final int bankFormat;

  const SoundRecord({
    required this.name,
    required this.nameHash,
    required this.sampleRate,
    required this.channels,
    required this.isStream,
    required this.skip,
    this.aliasFor,
    required this.dataSize,
    required this.audioOffset,
    required this.audioReadSize,
    required this.bankIndex,
    required this.substreamInterleave,
    required this.bankFormat,
  });

  // ── Computed display helpers ───────────────────────────────────────────────

  String get formattedOffset => '0x${audioOffset.toRadixString(16)}';
  String get channelLabel => channels == 2 ? 'stereo' : 'mono';
  String get typeLabel => isStream ? 'stream' : 'sample';

  @override
  String toString() =>
      'SoundRecord($name, rate=$sampleRate, ch=$channels, '
      'offset=$formattedOffset, size=$audioReadSize, bank=$bankIndex)';
}

/* Binary reference
Byte offset   Size  Tag (LE)     Field name    Meaning
  +0           4    0x37386ae0   "id"          FNV-1a name hash of the sound (see §5)
  +4           4    —            (value)       Name hash value
  +8           4    0x2fb31c01   "Frequency"   Sample rate tag
  +12          4    —            (value)       Sample rate in Hz (e.g. 44100, 22050, 11025)
  +16          4    0x23a0d95c   "size"        Audio data size tag
  +20          4    —            (value)       Byte count of raw audio for this entry
  +24          4    0x1d48feff   (unknown)     Unknown tag — possibly stream format flags
  +28          4    —            (value)       Unknown value
  +32          4    0x809608b6   "padding"     Post-audio padding tag
  +36          4    —            (value)       Bytes from end of audio to next SubStreamInterleave
                                               boundary; 0 for sample banks
  +40          4    see §3.4     "alias"/other Final field tag — platform-dependent (see §3.4)
  +44          4    —            (value)       Alias target hash (console) or skip indicator (PC)
*/