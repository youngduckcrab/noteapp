// Extension-point value types (contract 7.2.17, 04-editor 4.5; 2nd round:
// contract m5-7/00-overview 7.2.10, m5-7/04-editor 4.3.1 — the three new
// EditorExtensions fields, the selection / insert items and the image
// importer compare every field, functions as functions).
import 'package:feature_editor/feature_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

Future<void> _noop(BuildContext context, EditorMenuContext menu) async {}

Future<void> _other(BuildContext context, EditorMenuContext menu) async {}

Future<void> _onSelection(
  BuildContext context,
  EditorSelectionContext selection,
) async {}

Future<void> _onOtherSelection(
  BuildContext context,
  EditorSelectionContext selection,
) async {}

bool _visible(EditorSelectionContext selection) => true;

bool _otherVisible(EditorSelectionContext selection) => false;

Future<void> _onInsert(
  BuildContext context,
  EditorInsertContext insert,
) async {}

Future<void> _onOtherInsert(
  BuildContext context,
  EditorInsertContext insert,
) async {}

Widget _panel(BuildContext context, EditorPanelContext panel) =>
    const SizedBox();

Widget _otherPanel(BuildContext context, EditorPanelContext panel) =>
    const Placeholder();

Future<core.ImportedImage?> _pick(
  BuildContext context,
  core.ImageImportSource source,
) async => null;

Future<core.ImportedImage?> _otherPick(
  BuildContext context,
  core.ImageImportSource source,
) async => null;

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

    test('(v2.0) the new EditorExtensions fields default to empty / null', () {
      const extensions = EditorExtensions();
      expect(extensions.selectionMenuItems, isEmpty);
      expect(extensions.insertMenuItems, isEmpty);
      expect(extensions.recordingPanel, isNull);
      expect(extensions.moreMenuItems, isEmpty);
      expect(extensions.addPageSources, isEmpty);
      expect(extensions.appBarTrailing, isNull);
    });

    test('(v2.0) EditorExtensions compares the new fields', () {
      const selection = EditorSelectionMenuItem(
        id: 'recog.toText',
        label: '텍스트로',
        icon: Icons.text_fields,
        onSelected: _onSelection,
      );
      const otherSelection = EditorSelectionMenuItem(
        id: 'recog.toMath',
        label: '수식으로',
        icon: Icons.functions,
        onSelected: _onSelection,
      );
      const insert = EditorInsertMenuItem(
        id: 'recog.mathPad',
        label: '수식',
        icon: Icons.functions,
        onSelected: _onInsert,
      );
      final full = EditorExtensions(
        selectionMenuItems: [selection, otherSelection],
        insertMenuItems: [insert],
        recordingPanel: _panel,
      );
      final same = EditorExtensions(
        selectionMenuItems: [selection, otherSelection],
        insertMenuItems: [insert],
        recordingPanel: _panel,
      );
      expect(full, same);
      expect(full.hashCode, same.hashCode);
      final variants = <EditorExtensions>[
        // Order counts (ListEquality).
        EditorExtensions(
          selectionMenuItems: [otherSelection, selection],
          insertMenuItems: [insert],
          recordingPanel: _panel,
        ),
        EditorExtensions(
          selectionMenuItems: [selection],
          insertMenuItems: [insert],
          recordingPanel: _panel,
        ),
        EditorExtensions(
          selectionMenuItems: [selection, otherSelection],
          recordingPanel: _panel,
        ),
        EditorExtensions(
          selectionMenuItems: [selection, otherSelection],
          insertMenuItems: [insert],
        ),
        EditorExtensions(
          selectionMenuItems: [selection, otherSelection],
          insertMenuItems: [insert],
          recordingPanel: _otherPanel,
        ),
      ];
      for (final variant in variants) {
        expect(full, isNot(variant), reason: '$variant');
      }
      expect(
        full.toString(),
        allOf(contains('recog.toText'), contains('recog.mathPad')),
      );
    });

    test('(v2.0) EditorSelectionMenuItem compares every field', () {
      const item = EditorSelectionMenuItem(
        id: 'recog.toText',
        label: '텍스트로',
        icon: Icons.text_fields,
        onSelected: _onSelection,
        isVisible: _visible,
      );
      const same = EditorSelectionMenuItem(
        id: 'recog.toText',
        label: '텍스트로',
        icon: Icons.text_fields,
        onSelected: _onSelection,
        isVisible: _visible,
      );
      expect(item, same);
      expect(item.hashCode, same.hashCode);
      const variants = [
        EditorSelectionMenuItem(
          id: 'recog.copyText',
          label: '텍스트로',
          icon: Icons.text_fields,
          onSelected: _onSelection,
          isVisible: _visible,
        ),
        EditorSelectionMenuItem(
          id: 'recog.toText',
          label: '글자로',
          icon: Icons.text_fields,
          onSelected: _onSelection,
          isVisible: _visible,
        ),
        EditorSelectionMenuItem(
          id: 'recog.toText',
          label: '텍스트로',
          icon: Icons.functions,
          onSelected: _onSelection,
          isVisible: _visible,
        ),
        EditorSelectionMenuItem(
          id: 'recog.toText',
          label: '텍스트로',
          icon: Icons.text_fields,
          onSelected: _onOtherSelection,
          isVisible: _visible,
        ),
        EditorSelectionMenuItem(
          id: 'recog.toText',
          label: '텍스트로',
          icon: Icons.text_fields,
          onSelected: _onSelection,
          isVisible: _otherVisible,
        ),
        EditorSelectionMenuItem(
          id: 'recog.toText',
          label: '텍스트로',
          icon: Icons.text_fields,
          onSelected: _onSelection,
        ),
      ];
      for (final variant in variants) {
        expect(item, isNot(variant), reason: '$variant');
      }
    });

    test('(v2.0) EditorInsertMenuItem compares every field', () {
      const item = EditorInsertMenuItem(
        id: 'recog.mathPad',
        label: '수식',
        icon: Icons.functions,
        onSelected: _onInsert,
      );
      const same = EditorInsertMenuItem(
        id: 'recog.mathPad',
        label: '수식',
        icon: Icons.functions,
        onSelected: _onInsert,
      );
      expect(item, same);
      expect(item.hashCode, same.hashCode);
      const variants = [
        EditorInsertMenuItem(
          id: 'recog.other',
          label: '수식',
          icon: Icons.functions,
          onSelected: _onInsert,
        ),
        EditorInsertMenuItem(
          id: 'recog.mathPad',
          label: '수식 패드',
          icon: Icons.functions,
          onSelected: _onInsert,
        ),
        EditorInsertMenuItem(
          id: 'recog.mathPad',
          label: '수식',
          icon: Icons.add,
          onSelected: _onInsert,
        ),
        EditorInsertMenuItem(
          id: 'recog.mathPad',
          label: '수식',
          icon: Icons.functions,
          onSelected: _onOtherInsert,
        ),
      ];
      for (final variant in variants) {
        expect(item, isNot(variant), reason: '$variant');
      }
    });

    test('(v2.0) EditorImageImporter compares the source set and pick', () {
      const importer = EditorImageImporter(
        sources: {core.ImageImportSource.photos, core.ImageImportSource.camera},
        pick: _pick,
      );
      // Set order does not count.
      const reordered = EditorImageImporter(
        sources: {core.ImageImportSource.camera, core.ImageImportSource.photos},
        pick: _pick,
      );
      expect(importer, reordered);
      expect(importer.hashCode, reordered.hashCode);
      expect(
        importer,
        isNot(
          const EditorImageImporter(
            sources: {core.ImageImportSource.photos},
            pick: _pick,
          ),
        ),
      );
      expect(
        importer,
        isNot(
          const EditorImageImporter(
            sources: {
              core.ImageImportSource.photos,
              core.ImageImportSource.camera,
            },
            pick: _otherPick,
          ),
        ),
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
