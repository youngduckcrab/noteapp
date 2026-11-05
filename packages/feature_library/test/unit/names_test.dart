// validateItemName / normalizeItemName / uniqueName (05-library 6.12, 8 L1).
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateItemName', () {
    test('empty or only whitespace → empty', () {
      expect(validateItemName(''), NameIssue.empty);
      expect(validateItemName('   '), NameIssue.empty);
      expect(validateItemName('\t\n '), NameIssue.empty);
    });
    test('200 characters pass, 201 are too long (after trim)', () {
      expect(validateItemName('가' * 200), isNull);
      expect(validateItemName('  ${'가' * 200}  '), isNull);
      expect(validateItemName('가' * 201), NameIssue.tooLong);
      expect(kMaxItemNameLength, 200);
    });
    test('a normal name passes', () {
      expect(validateItemName(' 수학 노트 '), isNull);
    });
  });

  group('normalizeItemName', () {
    test('trims, collapses whitespace runs and lower-cases', () {
      expect(normalizeItemName('  New   Folder\t2 '), 'new folder 2');
      expect(normalizeItemName('수학'), '수학');
    });
  });

  group('uniqueName', () {
    const base = LibraryStrings.defaultFolderName; // '새 폴더'
    test('the base when it is free', () {
      expect(uniqueName(base, const []), '새 폴더');
      expect(uniqueName(base, const ['수학', '새 폴더 2']), '새 폴더');
    });
    test("'새 폴더 2' when the base is taken", () {
      expect(uniqueName(base, const ['새 폴더']), '새 폴더 2');
    });
    test('the first free number, also in a gap', () {
      expect(uniqueName(base, const ['새 폴더', '새 폴더 2', '새 폴더 4']), '새 폴더 3');
    });
    test('matches are normalized (case, spaces)', () {
      expect(uniqueName('Untitled', const [' untitled ']), 'Untitled 2');
      expect(uniqueName(base, const ['새  폴더', '새 폴더   2']), '새 폴더 3');
    });
    test('up to 999, then the base', () {
      final upTo998 = ['새 폴더', for (var n = 2; n <= 998; n++) '새 폴더 $n'];
      expect(uniqueName(base, upTo998), '새 폴더 999');
      expect(uniqueName(base, [...upTo998, '새 폴더 999']), '새 폴더');
    });
    test("default note title gives '제목 없는 노트 2'", () {
      expect(
        uniqueName(LibraryStrings.defaultNoteTitle, const ['제목 없는 노트']),
        '제목 없는 노트 2',
      );
    });
  });
}
