// AppRoutes and the route argument types (docs/plans/01-infra.md 4.5.5, 9.1).
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
  });
}
