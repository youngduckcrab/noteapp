import 'package:note_core/src/common/text_normalize.dart';
import 'package:test/test.dart';

void main() {
  test('NFD Hangul title composes to NFC (CORE 6.8 vector)', () {
    final nfd = String.fromCharCodes([
      0x1100, 0x1161, 0x11BC, 0x110B, 0x1174, 0x0020, //
      0x1102, 0x1169, 0x1110, 0x1173,
    ]);
    expect(normalizeForSearch(nfd), '강의 노트');
  });

  test('LV syllable + trailing jamo', () {
    expect(normalizeForSearch('가${String.fromCharCode(0x11BC)}'), '강');
  });

  test('lowercase, trim, collapse whitespace', () {
    expect(normalizeForSearch('  Hello   World '), 'hello world');
    expect(normalizeForSearch('A\t\nB'), 'a b');
  });

  test('an NFD title is found with an NFC query', () {
    final title = normalizeForSearch(
      String.fromCharCodes([0x1112, 0x1161, 0x11AB, 0x1100, 0x1173, 0x11AF]),
    ); // 한글
    expect(title.contains(normalizeForSearch('한')), isTrue);
    expect(title, '한글');
  });

  test('other characters are left alone', () {
    expect(normalizeForSearch('Café 노트 №1'), 'café 노트 №1');
    // A lone conjoining vowel / trailing consonant stays as is.
    final lone = String.fromCharCodes([0x1161, 0x11A8]);
    expect(normalizeForSearch(lone), lone);
  });
}
