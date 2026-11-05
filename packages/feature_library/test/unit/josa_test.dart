// KoreanJosa (05-library 6.18, 8 L1).
import 'package:feature_library/src/l10n/korean_josa.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('6.18 examples', () {
    final cases = <(String, String, String)>[
      ('수학', '을', '으로'),
      ('영어', '를', '로'),
      ('물리', '를', '로'),
      ('국어 1', '을', '로'),
      ('Math', '을(를)', '(으)로'),
    ];
    for (final (word, object, direction) in cases) {
      test(word, () {
        expect(KoreanJosa.object(word), object);
        expect(KoreanJosa.direction(word), direction);
      });
    }
  });

  group('Hangul final consonants', () {
    test('ㄹ takes 을 but 로', () {
      expect(KoreanJosa.object('서울'), '을');
      expect(KoreanJosa.direction('서울'), '로');
    });
    test('other finals take 을 / 으로', () {
      expect(KoreanJosa.object('책'), '을');
      expect(KoreanJosa.direction('책'), '으로');
      expect(KoreanJosa.direction('힣'), '으로'); // U+D7A3, last syllable
    });
    test('no final takes 를 / 로', () {
      expect(KoreanJosa.object('가'), '를'); // U+AC00, first syllable
      expect(KoreanJosa.direction('노트'), '로');
    });
  });

  group('digits by their reading', () {
    final cases = <(String, String, String)>[
      ('0', '을', '으로'), // 영
      ('1', '을', '로'), // 일
      ('2', '를', '로'), // 이
      ('3', '을', '으로'), // 삼
      ('4', '를', '로'), // 사
      ('5', '를', '로'), // 오
      ('6', '을', '으로'), // 육
      ('7', '을', '로'), // 칠
      ('8', '을', '로'), // 팔
      ('9', '를', '로'), // 구
    ];
    for (final (digit, object, direction) in cases) {
      test('노트 $digit', () {
        expect(KoreanJosa.object('노트 $digit'), object);
        expect(KoreanJosa.direction('노트 $digit'), direction);
      });
    }
  });

  group('other characters', () {
    test('symbols, empty and a non-syllable jamo give both forms', () {
      for (final word in ['메모!', '', '   ', 'ㄱ', '노트)']) {
        expect(KoreanJosa.object(word), '을(를)', reason: word);
        expect(KoreanJosa.direction(word), '(으)로', reason: word);
      }
    });
    test('trailing spaces are ignored', () {
      expect(KoreanJosa.object('수학  '), '을');
    });
  });

  test('LibraryStrings quotes the name and adds the particle', () {
    expect(LibraryStrings.quotedWithObject('수학'), "'수학'을");
    expect(LibraryStrings.quotedWithDirection('영어'), "'영어'로");
  });
}
