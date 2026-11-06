// CORE T6 vectors (1st round) + (v2, m5-7/02-core 6.10.1 — review S-16, CORE T24) the
// delegation: normalizeForSearch is SearchText.normalize, so steps 1 (line-end hyphen join),
// 2 (zero-width / soft hyphen removed) and 5 (per-code-point lowercase) now apply to
// name_norm / title_norm and to title queries — on both stores' write paths.
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/common/text_normalize.dart';
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';
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

  group('v2: SearchText.normalize (6.10.1)', () {
    test('step 1: a line-end hyphen between letters is joined', () {
      expect(normalizeForSearch('Lehr-\nbuch'), 'lehrbuch');
      expect(normalizeForSearch('Lehr-\r\nbuch'), 'lehrbuch');
      expect(
        normalizeForSearch('A-\n 1'),
        'a- 1',
      ); // not letter-hyphen-newline-letter
    });

    test('step 2: soft hyphen and zero-width characters are removed', () {
      expect(normalizeForSearch('No\u00ADte'), 'note');
      expect(normalizeForSearch('a\u200Bb\u200Cc\u200Dd\uFEFFe'), 'abcde');
    });

    test('step 3: NBSP and ideographic space are whitespace', () {
      expect(normalizeForSearch('a\u00A0\u3000 b'), 'a b');
    });

    test('step 5: lowercase per code point (no final-sigma rule)', () {
      expect(normalizeForSearch('ΟΔΟΣ'), 'οδοσ');
      expect(normalizeForSearch('İ'), 'i');
    });

    test('normalizeForSearch == SearchText.normalize', () {
      for (final s in [
        '',
        '  Hello   World ',
        'Café 노트 №1',
        String.fromCharCodes([0x1100, 0x1161, 0x11BC]),
        'Lehr-\nbuch',
        'x\u00ADy',
      ]) {
        expect(normalizeForSearch(s), SearchText.normalize(s), reason: s);
      }
    });

    for (final (name, open) in [
      ('fake store', () async => createFakeNoteStore()),
      ('real store', openTestNoteStore),
    ]) {
      test('$name: the write path and the title search use it', () async {
        final store = await open();
        addTearDown(store.close);
        final folder = await store.library.createFolder(name: 'Ab\u200Bc');
        final note = await store.library.createNote(title: 'Lehr-\nbuch');
        final byName = await store.library.searchLibrary('abc');
        expect(byName.folders.map((f) => f.id), [folder.id]);
        final byTitle = await store.library.searchLibrary('LEHRBUCH');
        expect(byTitle.notes.map((n) => n.id), [note.id]);
      });
    }
  });
}
