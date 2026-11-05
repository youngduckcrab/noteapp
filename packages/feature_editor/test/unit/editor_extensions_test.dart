// Extension-point value types (contract 7.2.17, 04-editor 4.5).
import 'package:feature_editor/feature_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _noop(BuildContext context, EditorMenuContext menu) async {}

Future<void> _other(BuildContext context, EditorMenuContext menu) async {}

EditorMenuContext _menu(List<String> pageIds, int index) => EditorMenuContext(
  noteId: 'n',
  pageIds: pageIds,
  currentPageIndex: index,
  navigateToPage: (pageId, focusRectPt) {},
);

void main() {
  group('EditorMenuContext.currentPageId', () {
    test('is pageIds[currentPageIndex] inside the list', () {
      expect(_menu(['a', 'b', 'c'], 0).currentPageId, 'a');
      expect(_menu(['a', 'b', 'c'], 2).currentPageId, 'c');
    });

    test('is null outside the list (4.5 table)', () {
      expect(_menu(['a', 'b'], 2).currentPageId, isNull);
      expect(_menu(['a'], -1).currentPageId, isNull);
      expect(_menu([], 0).currentPageId, isNull);
    });

    test('selectedPageIds defaults to an empty list', () {
      expect(_menu(['a'], 0).selectedPageIds, isEmpty);
      final menu = EditorMenuContext(
        noteId: 'n',
        pageIds: const ['a', 'b'],
        currentPageIndex: 0,
        selectedPageIds: const ['b'],
        navigateToPage: (pageId, focusRectPt) {},
      );
      expect(menu.selectedPageIds, ['b']);
    });
  });

  group('value equality (contract 7.4.4: provider values)', () {
    const item = EditorMenuItem(
      id: 'pdf.export',
      label: 'PDF',
      icon: Icons.picture_as_pdf,
      onSelected: _noop,
    );

    test('EditorMenuItem compares every field', () {
      const same = EditorMenuItem(
        id: 'pdf.export',
        label: 'PDF',
        icon: Icons.picture_as_pdf,
        onSelected: _noop,
      );
      expect(item, same);
      expect(item.hashCode, same.hashCode);
      const otherId = EditorMenuItem(
        id: 'pdf.share',
        label: 'PDF',
        icon: Icons.picture_as_pdf,
        onSelected: _noop,
      );
      const otherAction = EditorMenuItem(
        id: 'pdf.export',
        label: 'PDF',
        icon: Icons.picture_as_pdf,
        onSelected: _other,
      );
      expect(item, isNot(otherId));
      expect(item, isNot(otherAction));
    });

    test('EditorExtensions compares the item lists by content', () {
      expect(
        EditorExtensions(moreMenuItems: [item]),
        EditorExtensions(moreMenuItems: [item]),
      );
      expect(
        EditorExtensions(moreMenuItems: [item]).hashCode,
        EditorExtensions(moreMenuItems: [item]).hashCode,
      );
      expect(
        EditorExtensions(moreMenuItems: [item]),
        isNot(EditorExtensions(addPageSources: [item])),
      );
      expect(
        const EditorExtensions(),
        isNot(EditorExtensions(appBarTrailing: (context) => const SizedBox())),
      );
    });

    test('DevOverlaySection compares id, title and the listenable', () {
      final lines = ValueNotifier<List<String>>(const []);
      addTearDown(lines.dispose);
      final other = ValueNotifier<List<String>>(const []);
      addTearDown(other.dispose);
      final a = DevOverlaySection(id: 'x', title: 'X', lines: lines);
      expect(a, DevOverlaySection(id: 'x', title: 'X', lines: lines));
      expect(a, isNot(DevOverlaySection(id: 'x', title: 'X', lines: other)));
      expect(a, isNot(DevOverlaySection(id: 'y', title: 'X', lines: lines)));
    });
  });
}
