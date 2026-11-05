// lib/src/l10n/korean_josa.dart — 05-library 6.18 (을/를, (으)로).
//
// Last character c of the (trimmed) word:
// - Hangul syllable (U+AC00..U+D7A3): jong = (c - 0xAC00) % 28, 0 = no final
//   consonant, 8 = ㄹ.
// - ASCII digit: the final consonant of how it is read — 0 영(ㅇ) 1 일(ㄹ)
//   2 이(-) 3 삼(ㅁ) 4 사(-) 5 오(-) 6 육(ㄱ) 7 칠(ㄹ) 8 팔(ㄹ) 9 구(-).
// - Anything else (Latin letters, symbols, empty): both forms '을(를)' /
//   '(으)로'.

/// Korean particles chosen by the final consonant of a word.
abstract final class KoreanJosa {
  /// '을' after a final consonant, '를' otherwise.
  static String object(String word) => switch (_finalOf(word)) {
    _Final.none => '를',
    _Final.rieul || _Final.other => '을',
    _Final.unknown => '을(를)',
  };

  /// '으로' after a final consonant except ㄹ, '로' otherwise.
  static String direction(String word) => switch (_finalOf(word)) {
    _Final.none || _Final.rieul => '로',
    _Final.other => '으로',
    _Final.unknown => '(으)로',
  };
}

enum _Final { none, rieul, other, unknown }

const int _hangulFirst = 0xAC00;
const int _hangulLast = 0xD7A3;
const int _jongCount = 28;
const int _jongRieul = 8;
const int _digitZero = 0x30;

/// Final consonant of each digit's reading, index = digit.
const List<_Final> _digitFinals = [
  _Final.other, // 영
  _Final.rieul, // 일
  _Final.none, // 이
  _Final.other, // 삼
  _Final.none, // 사
  _Final.none, // 오
  _Final.other, // 육
  _Final.rieul, // 칠
  _Final.rieul, // 팔
  _Final.none, // 구
];

_Final _finalOf(String word) {
  final trimmed = word.trimRight();
  if (trimmed.isEmpty) return _Final.unknown;
  final c = trimmed.codeUnitAt(trimmed.length - 1);
  if (c >= _hangulFirst && c <= _hangulLast) {
    final jong = (c - _hangulFirst) % _jongCount;
    if (jong == 0) return _Final.none;
    return jong == _jongRieul ? _Final.rieul : _Final.other;
  }
  final digit = c - _digitZero;
  if (digit >= 0 && digit <= 9) return _digitFinals[digit];
  return _Final.unknown;
}
