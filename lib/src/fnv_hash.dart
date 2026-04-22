/// FNV-1a hash matching the BF2 munge tool's HashString algorithm.
///
/// Each character is lowercased via `| 0x20` before hashing (matching the
/// VB implementation's `c Or &H20`). Result is an unsigned 32-bit integer.
int fnvHash(String input) {
  const int prime = 16777619;
  const int offsetBasis = 2166136261;
  int hash = offsetBasis;
  for (int i = 0; i < input.length; i++) {
    final int c = input.codeUnitAt(i) | 0x20;
    hash ^= c;
    hash = (hash * prime) & 0xFFFFFFFF;
  }
  return hash;
}
