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
    final runes = text.runes.toList();
    final out = <int>[];
    var i = 0;
    while (i < runes.length) {
      final c = runes[i];
      if (_isL(c) && i + 1 < runes.length && _isV(runes[i + 1])) {
        var syllable =
            _sBase +
            ((c - _lBase) * _vCount + (runes[i + 1] - _vBase)) * _tCount;
        i += 2;
        if (i < runes.length && _isT(runes[i])) {
          syllable += runes[i] - _tBase;
          i++;
        }
        out.add(syllable);
        continue;
      }
      if (_isLV(c) && i + 1 < runes.length && _isT(runes[i + 1])) {
        out.add(c + runes[i + 1] - _tBase);
        i += 2;
        continue;
      }
      out.add(c);
      i++;
    }
    return String.fromCharCodes(out);
  }

  static bool _hasJamo(String text) {
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c >= 0x1100 && c <= 0x11FF) return true;
    }
    return false;
  }
}
