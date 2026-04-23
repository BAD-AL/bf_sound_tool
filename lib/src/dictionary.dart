import 'dictionary_data.dart';
import 'fnv_hash.dart';

/// Maps FNV-1a hashes back to their original sound name strings.
class Dictionary {
  final Map<int, String> _map = {};

  /// Add a single name, computing its hash automatically.
  void addName(String name) {
    final hash = fnvHash(name);
    _map[hash] = name;
  }

  /// Add all names from [lines], skipping blank lines and trimming whitespace.
  void loadLines(Iterable<String> lines) {
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) addName(trimmed);
    }
  }

  /// Add all names from a multi-line string — splits on newlines and trims each.
  void loadString(String text) => loadLines(text.split('\n'));

  /// Load the embedded BF1/BF2 built-in dictionary (33 000+ entries).
  void loadBuiltin() => loadString(kBuiltinDictionary);

  /// Returns the name for [hash], or null if not found.
  String? lookup(int hash) => _map[hash];

  /// Returns the name for [hash], or a hex fallback string like '0x7a849cde'.
  String resolve(int hash) =>
      _map[hash] ?? '0x${hash.toRadixString(16).padLeft(8, '0')}';
}
