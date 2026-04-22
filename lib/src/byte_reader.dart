import 'dart:typed_data';

/// Sequential little-endian reader over a byte buffer.
class ByteReader {
  final Uint8List _data;
  int position;

  ByteReader(this._data, {this.position = 0});

  int get length => _data.length;
  bool get isAtEnd => position >= _data.length;
  int get remaining => _data.length - position;

  int readUint8() => _data[position++];

  int readUint16() {
    final v = _data[position] | (_data[position + 1] << 8);
    position += 2;
    return v;
  }

  int readUint32() {
    final v = _data[position] |
        (_data[position + 1] << 8) |
        (_data[position + 2] << 16) |
        (_data[position + 3] << 24);
    position += 4;
    // Ensure unsigned interpretation on all platforms.
    return v & 0xFFFFFFFF;
  }

  Uint8List readBytes(int count) {
    final bytes = Uint8List.fromList(_data.sublist(position, position + count));
    position += count;
    return bytes;
  }

  void seek(int offset) => position = offset;
  void skip(int count) => position += count;

  /// Read uint32 LE at [at] (or current position) without moving position.
  int peekUint32([int? at]) {
    final p = at ?? position;
    return (_data[p] |
            (_data[p + 1] << 8) |
            (_data[p + 2] << 16) |
            (_data[p + 3] << 24)) &
        0xFFFFFFFF;
  }

  /// Returns a new ByteReader over the sub-range [offset, offset+length).
  ByteReader slice(int offset, int length) =>
      ByteReader(Uint8List.fromList(_data.sublist(offset, offset + length)));
}
