// AppRoutes and the route argument types (docs/plans/01-infra.md 4.5.5, 9.1;
// 2차 docs/plans/m5-7/01-infra.md 4.6.6, 6.8 — FocusRectCodec, ?focus=).
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/src/routing/app_routes.dart';

void main() {
  test('route patterns and the page query key', () {
    expect(AppRoutes.library, '/');
    expect(AppRoutes.folderPattern, '/folders/:folderId');
    expect(AppRoutes.notePattern, '/notes/:noteId');
    expect(AppRoutes.settings, '/settings');
    expect(AppRoutes.pageQueryKey, 'page');
    expect(AppRoutes.focusQueryKey, 'focus');
  });

  test('folder paths encode the id as one path segment', () {
    expect(AppRoutes.folder('f1'), '/folders/f1');
    expect(AppRoutes.folder('a/b c'), '/folders/a%2Fb%20c');
    expect(AppRoutes.folder('폴더?#'), '/folders/%ED%8F%B4%EB%8D%94%3F%23');
    expect(Uri.parse(AppRoutes.folder('a/b c')).pathSegments, [
      'folders',
      'a/b c',
    ]);
  });

  test('note paths encode the id and add ?page= only when given', () {
    expect(AppRoutes.note('n1'), '/notes/n1');
    expect(AppRoutes.note('n1', pageId: 'p3'), '/notes/n1?page=p3');
    expect(AppRoutes.note('a/b', pageId: 'p 3&x'), '/notes/a%2Fb?page=p+3%26x');

    final uri = Uri.parse(AppRoutes.note('a/b?c', pageId: 'p 3&x=y#z'));
    expect(uri.pathSegments, ['notes', 'a/b?c']);
    expect(uri.queryParameters, {AppRoutes.pageQueryKey: 'p 3&x=y#z'});
    expect(uri.fragment, isEmpty);
  });

  group('?focus= (2차 6.8)', () {
    test('note(pageId:, focus:) adds &focus=l,t,r,b with plain commas', () {
      expect(
        AppRoutes.note(
          'n1',
          pageId: 'p3',
          focus: const Rect.fromLTRB(120, 80, 320.5, 200),
        ),
        '/notes/n1?page=p3&focus=120,80,320.5,200',
      );
      final uri = Uri.parse(
        AppRoutes.note(
          'a/b',
          pageId: 'p 3&x',
          focus: const Rect.fromLTRB(-1.25, 0, 2, 3.04),
        ),
      );
      expect(uri.pathSegments, ['notes', 'a/b']);
      expect(uri.queryParameters, {
        AppRoutes.pageQueryKey: 'p 3&x',
        AppRoutes.focusQueryKey: '-1.3,0,2,3',
      });
      expect(uri.query, contains('focus=-1.3,0,2,3'));
    });

    test('focus without pageId is asserted in debug', () {
      expect(
        () => AppRoutes.note('n1', focus: const Rect.fromLTRB(0, 0, 1, 1)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a focus that decode would not read back is left out', () {
      for (final rect in [
        const Rect.fromLTRB(10, 0, 5, 5), // l > r
        const Rect.fromLTRB(0, 10, 5, 5), // t > b
        const Rect.fromLTRB(0, 0, 100001, 5), // beyond the limit
        const Rect.fromLTRB(0, 0, double.infinity, 5),
        const Rect.fromLTRB(double.nan, 0, 1, 1),
      ]) {
        expect(
          AppRoutes.note('n1', pageId: 'p3', focus: rect),
          '/notes/n1?page=p3',
          reason: '$rect',
        );
        expect(FocusRectCodec.canEncode(rect), isFalse, reason: '$rect');
      }
    });

    test('encode rounds to 0.1 pt and drops a trailing .0', () {
      expect(FocusRectCodec.encode(Rect.zero), '0,0,0,0');
      expect(
        FocusRectCodec.encode(const Rect.fromLTRB(1.0, 2.5, 3.04, 4.06)),
        '1,2.5,3,4.1',
      );
      expect(
        FocusRectCodec.encode(const Rect.fromLTRB(-0.04, -0.06, -7.96, 0.96)),
        '0,-0.1,-8,1',
      );
      expect(
        () => FocusRectCodec.encode(const Rect.fromLTRB(0, 0, 1, double.nan)),
        throwsArgumentError,
      );
    });

    // 20 round trips: decimals, negatives, zero size, large values.
    const roundTrips = <(Rect, Rect)>[
      (Rect.fromLTRB(0, 0, 10, 10), Rect.fromLTRB(0, 0, 10, 10)),
      (Rect.fromLTRB(120, 80, 320.5, 200), Rect.fromLTRB(120, 80, 320.5, 200)),
      (Rect.fromLTRB(0.1, 0.2, 0.3, 0.4), Rect.fromLTRB(0.1, 0.2, 0.3, 0.4)),
      (Rect.fromLTRB(1.04, 2.06, 3.16, 4.94), Rect.fromLTRB(1, 2.1, 3.2, 4.9)),
      (
        Rect.fromLTRB(-50, -20.5, -10, -0.5),
        Rect.fromLTRB(-50, -20.5, -10, -0.5),
      ),
      (Rect.fromLTRB(-0.04, -0.04, 0.04, 0.04), Rect.zero),
      (Rect.fromLTRB(5, 5, 5, 5), Rect.fromLTRB(5, 5, 5, 5)),
      (Rect.fromLTRB(5, 5, 5, 9.5), Rect.fromLTRB(5, 5, 5, 9.5)),
      (Rect.fromLTRB(5.5, 5, 9, 5), Rect.fromLTRB(5.5, 5, 9, 5)),
      (
        Rect.fromLTRB(0, 0, 100000, 100000),
        Rect.fromLTRB(0, 0, 100000, 100000),
      ),
      (
        Rect.fromLTRB(-100000, -100000, 100000, 100000),
        Rect.fromLTRB(-100000, -100000, 100000, 100000),
      ),
      (
        Rect.fromLTRB(99999.94, 0, 99999.96, 1),
        Rect.fromLTRB(99999.9, 0, 100000, 1),
      ),
      (
        Rect.fromLTRB(612, 792, 1224, 1584),
        Rect.fromLTRB(612, 792, 1224, 1584),
      ),
      (
        Rect.fromLTRB(36.25, 72.75, 300, 400),
        Rect.fromLTRB(36.3, 72.8, 300, 400),
      ),
      (
        Rect.fromLTRB(10.01, 10.09, 10.11, 10.19),
        Rect.fromLTRB(10, 10.1, 10.1, 10.2),
      ),
      (
        Rect.fromLTRB(-3.33, 4.44, 5.56, 6.66),
        Rect.fromLTRB(-3.3, 4.4, 5.6, 6.7),
      ),
      (Rect.fromLTRB(0, 0, 0.06, 0.06), Rect.fromLTRB(0, 0, 0.1, 0.1)),
      (Rect.fromLTRB(-1, -1, 0, 0), Rect.fromLTRB(-1, -1, 0, 0)),
      (Rect.fromLTRB(1e-9, 2e-9, 1, 1), Rect.fromLTRB(0, 0, 1, 1)),
      (
        Rect.fromLTRB(768.5, 1024, 1032, 1376),
        Rect.fromLTRB(768.5, 1024, 1032, 1376),
      ),
    ];
    for (final (rect, rounded) in roundTrips) {
      test('round trip $rect', () {
        final text = FocusRectCodec.encode(rect);
        expect(text, isNot(contains('%')));
        expect(text, isNot(contains('.0,')));
        expect(text, isNot(endsWith('.0')));
        final back = FocusRectCodec.decode(text)!;
        for (final (a, b) in [
          (back.left, rounded.left),
          (back.top, rounded.top),
          (back.right, rounded.right),
          (back.bottom, rounded.bottom),
        ]) {
          expect(a, moreOrLessEquals(b, epsilon: 1e-9));
        }
        // Encoding again gives the same text (stable after one rounding).
        expect(FocusRectCodec.encode(back), text);
        // The address carries it unchanged.
        final uri = Uri.parse(AppRoutes.note('n', pageId: 'p', focus: rect));
        expect(uri.queryParameters[AppRoutes.focusQueryKey], text);
      });
    }

    test('decode accepts %2C (either case) as a comma', () {
      expect(
        FocusRectCodec.decode('1%2C2%2c3%2C4'),
        const Rect.fromLTRB(1, 2, 3, 4),
      );
      expect(
        FocusRectCodec.decode(Uri.encodeQueryComponent('120,80,320.5,200')),
        const Rect.fromLTRB(120, 80, 320.5, 200),
      );
    });

    // 9 bad values → null (the page still opens without focus).
    const invalid = <String?>[
      null,
      '',
      '1,2,3', // three values
      '1,2,3,4,5', // five values
      'a,b,c,d', // not numbers
      '1,2,Infinity,4', // not finite
      '10,0,5,5', // l > r
      '0,10,5,5', // t > b
      '0,0,100000.1,5', // beyond ±100000
    ];
    for (final value in invalid) {
      test('decode(${value == null ? 'null' : "'$value'"}) → null', () {
        expect(FocusRectCodec.decode(value), isNull);
      });
    }

    test('decode rejects what encode never writes', () {
      for (final value in [
        '1,,2,3',
        ' 1,2,3,4',
        '+1,2,3,4',
        '1e3,2,3,4',
        'NaN,2,3,4',
        '0x10,2,3,4',
        '1.,2,3,4',
        '.5,2,3,4',
        '1;2;3;4',
      ]) {
        expect(FocusRectCodec.decode(value), isNull, reason: value);
      }
    });
  });

  test('libraryPageKey is one shared ValueKey', () {
    expect(AppRoutes.libraryPageKey, const ValueKey<String>('library'));
  });

  test('route args compare by value', () {
    expect(const LibraryRouteArgs(), const LibraryRouteArgs(folderId: null));
    expect(
      const LibraryRouteArgs(folderId: 'f1'),
      const LibraryRouteArgs(folderId: 'f1'),
    );
    expect(
      const LibraryRouteArgs(folderId: 'f1'),
      isNot(const LibraryRouteArgs(folderId: 'f2')),
    );
    expect(
      const LibraryRouteArgs(folderId: 'f1').hashCode,
      const LibraryRouteArgs(folderId: 'f1').hashCode,
    );

    expect(
      const EditorRouteArgs(noteId: 'n1', initialPageId: 'p3'),
      const EditorRouteArgs(noteId: 'n1', initialPageId: 'p3'),
    );
    expect(
      const EditorRouteArgs(noteId: 'n1'),
      isNot(const EditorRouteArgs(noteId: 'n1', initialPageId: 'p3')),
    );
    expect(
      const EditorRouteArgs(noteId: 'n1', initialPageId: 'p3').hashCode,
      const EditorRouteArgs(noteId: 'n1', initialPageId: 'p3').hashCode,
    );

    const focus = Rect.fromLTRB(1, 2, 3, 4);
    expect(
      const EditorRouteArgs(
        noteId: 'n1',
        initialPageId: 'p3',
        initialFocusRectPt: focus,
      ),
      const EditorRouteArgs(
        noteId: 'n1',
        initialPageId: 'p3',
        initialFocusRectPt: Rect.fromLTRB(1, 2, 3, 4),
      ),
    );
    expect(
      const EditorRouteArgs(
        noteId: 'n1',
        initialPageId: 'p3',
        initialFocusRectPt: focus,
      ).hashCode,
      const EditorRouteArgs(
        noteId: 'n1',
        initialPageId: 'p3',
        initialFocusRectPt: focus,
      ).hashCode,
    );
    expect(
      const EditorRouteArgs(noteId: 'n1', initialPageId: 'p3'),
      isNot(
        const EditorRouteArgs(
          noteId: 'n1',
          initialPageId: 'p3',
          initialFocusRectPt: focus,
        ),
      ),
    );
    expect(
      const EditorRouteArgs(
        noteId: 'n1',
        initialPageId: 'p3',
        initialFocusRectPt: focus,
      ).toString(),
      contains('initialFocusRectPt'),
    );
  });

  test('EditorRouteArgs: a focus without a page is asserted', () {
    EditorRouteArgs withoutPage(Rect focus) =>
        EditorRouteArgs(noteId: 'n1', initialFocusRectPt: focus);
    expect(
      () => withoutPage(const Rect.fromLTRB(0, 0, 1, 1)),
      throwsA(isA<AssertionError>()),
    );
  });
}
