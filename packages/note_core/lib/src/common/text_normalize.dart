// lib/src/common/text_normalize.dart — internal, shared by the DB store and the fake store
// (CORE 4.1, 6.8).

const int _sBase = 0xAC00;
const int _lBase = 0x1100;
const int _vBase = 0x1161;
const int _tBase = 0x11A7; // T index 1..27 = U+11A8..U+11C2
const int _lCount = 19;
const int _vCount = 21;
const int _tCount = 28;
const int _sCount = _lCount * _vCount * _tCount; // 11172

final RegExp _spaces = RegExp(r'\s+');

bool _isL(int c) => c >= _lBase && c < _lBase + _lCount; // U+1100..U+1112
bool _isV(int c) => c >= _vBase && c < _vBase + _vCount; // U+1161..U+1175
bool _isT(int c) => c > _tBase && c < _tBase + _tCount; // U+11A8..U+11C2
bool _isLvSyllable(int c) =>
    c >= _sBase && c < _sBase + _sCount && (c - _sBase) % _tCount == 0;

/// name_norm / search query form (6.8): Hangul conjoining jamo composed into syllables
/// (U+1100..U+1112 + U+1161..U+1175 [+ U+11A8..U+11C2], and LV syllable + trailing jamo),
/// then lowercased, trimmed, runs of whitespace collapsed to one space.
String normalizeForSearch(String text) =>
    _composeHangul(text).toLowerCase().trim().replaceAll(_spaces, ' ');

String _composeHangul(String text) {
  final units = text.codeUnits;
  final out = <int>[];
  var i = 0;
  while (i < units.length) {
    final c = units[i];
    if (_isL(c) && i + 1 < units.length && _isV(units[i + 1])) {
      var s =
          _sBase + ((c - _lBase) * _vCount + (units[i + 1] - _vBase)) * _tCount;
      i += 2;
      if (i < units.length && _isT(units[i])) {
        s += units[i] - _tBase;
        i++;
      }
      out.add(s);
      continue;
    }
    if (_isLvSyllable(c) && i + 1 < units.length && _isT(units[i + 1])) {
      out.add(c + units[i + 1] - _tBase);
      i += 2;
      continue;
    }
    out.add(c);
    i++;
  }
  return String.fromCharCodes(out);
}
