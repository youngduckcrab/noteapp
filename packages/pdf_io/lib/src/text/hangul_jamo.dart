// lib/src/text/hangul_jamo.dart — internal (not exported), 06-pdf 4.8, 6.10.1.

abstract final class HangulJamo {
  static const int _sBase = 0xAC00, _sCount = 11172;
  static const int _lBase = 0x1100, _lCount = 19; // U+1100..U+1112
  static const int _vBase = 0x1161, _vCount = 21; // U+1161..U+1175
  /// T: U+11A8..U+11C2 (index 0 = no final consonant)
  static const int _tBase = 0x11A7, _tCount = 28;

  static bool _isL(int c) => c >= _lBase && c < _lBase + _lCount;
  static bool _isV(int c) => c >= _vBase && c < _vBase + _vCount;
  static bool _isT(int c) => c > _tBase && c < _tBase + _tCount;

  /// LV syllable: a precomposed syllable without a final consonant.
  static bool _isLV(int c) =>
      c >= _sBase && c < _sBase + _sCount && (c - _sBase) % _tCount == 0;

  /// Step 4 of 6.10.1 only: L (U+1100..U+1112) + V (U+1161..U+1175) [+ T (U+11A8..U+11C2)]
  /// and LV syllable + T → precomposed syllable. Other text unchanged.
  static String compose(String text) {
    if (!_hasJamo(text)) return text;
    final out = <int>[];
    var i = 0;
    while (i < text.length) {
      final syllable = syllableAt(text, i);
      if (syllable != null) {
        out.add(syllable.syllable);
        i += syllable.length;
        continue;
      }
      out.add(text.codeUnitAt(i));
      i++;
    }
    return String.fromCharCodes(out);
  }

  /// The syllable composed from the jamo sequence starting at code unit [index] of [text]
  /// (L + V [+ T], or LV syllable + T) and how many code units it uses; null when no
  /// sequence starts there. All jamo and syllables are BMP, so code units = characters.
  /// Shared by [compose] and PdfTextNormalizer (6.10.1 step 4).
  static ({int syllable, int length})? syllableAt(String text, int index) {
    final n = text.length;
    final c = text.codeUnitAt(index);
    if (_isL(c) && index + 1 < n && _isV(text.codeUnitAt(index + 1))) {
      var syllable =
          _sBase +
          ((c - _lBase) * _vCount + (text.codeUnitAt(index + 1) - _vBase)) *
              _tCount;
      var length = 2;
      if (index + 2 < n && _isT(text.codeUnitAt(index + 2))) {
        syllable += text.codeUnitAt(index + 2) - _tBase;
        length = 3;
      }
      return (syllable: syllable, length: length);
    }
    if (_isLV(c) && index + 1 < n && _isT(text.codeUnitAt(index + 1))) {
      return (syllable: c + text.codeUnitAt(index + 1) - _tBase, length: 2);
    }
    return null;
  }

  static bool _hasJamo(String text) {
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c >= 0x1100 && c <= 0x11FF) return true;
    }
    return false;
  }
}
