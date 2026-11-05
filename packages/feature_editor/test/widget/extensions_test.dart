// E-13: extension items in the more menu (04-editor 4.5, 6.11.5): they get
// the EditorMenuContext built when the menu opens (noteId, pageIds in note
// order, currentPageId, selectedPageIds, navigateToPage), isEnabled false →
// greyed (not hidden), one run at a time, an exception → reported + snack
// bar. addPageSources (the add-page sheet's '다른 소스' row) are checked with
// E-17.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/pump_editor.dart';

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pumpAndSettle();
}

Future<void> _tapItem(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(EditorMoreMenu.itemKey(id)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an item gets the menu context and can navigate', (tester) async {
    final received = <EditorMenuContext>[];
    BuildContext? usedContext;
    final h = await pumpEditor(
      tester,
      pages: 4,
      overrides: [
        editorExtensionsProvider.overrideWithValue(
          EditorExtensions(
            moreMenuItems: [
              EditorMenuItem(
                id: 'test.export',
                label: '내보내기',
                icon: Icons.ios_share,
                onSelected: (context, menu) async {
                  usedContext = context;
                  received.add(menu);
                },
              ),
            ],
          ),
        ),
      ],
    );
    await h.viewport.jumpToPage(1, animate: false);
    await tester.pump(const Duration(milliseconds: 200));

    await _openMore(tester);
    expect(find.text('내보내기'), findsOneWidget);
    await _tapItem(tester, 'test.export');
    expect(received, hasLength(1));
    final menu = received.single;
    expect(menu.noteId, h.noteId);
    expect(menu.pageIds, [for (var i = 0; i < 4; i++) h.pageId(i)]);
    expect(menu.currentPageIndex, 1);
    expect(menu.currentPageId, h.pageId(1));
    expect(menu.selectedPageIds, isEmpty);
    expect(usedContext!.mounted, isTrue);
    expect(find.text('내보내기'), findsNothing, reason: 'the menu closed');

    // navigateToPage: a known page → current page; an unknown id → ignored.
    menu.navigateToPage(h.pageId(3), null);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.viewport.currentPageIndex.value, 3);
    menu.navigateToPage('no-such-page', null);
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.viewport.currentPageIndex.value, 3);
  });

  testWidgets('isEnabled false → shown but greyed; isEnabled sees the menu '
      'context', (tester) async {
    EditorMenuContext? asked;
    var ran = 0;
    await pumpEditor(
      tester,
      overrides: [
        editorExtensionsProvider.overrideWithValue(
          EditorExtensions(
            moreMenuItems: [
              EditorMenuItem(
                id: 'test.off',
                label: '꺼진 항목',
                icon: Icons.block,
                isEnabled: (menu) {
                  asked = menu;
                  return false;
                },
                onSelected: (context, menu) async => ran++,
              ),
            ],
          ),
        ),
      ],
    );
    await _openMore(tester);
    final item = find.byKey(EditorMoreMenu.itemKey('test.off'));
    expect(item, findsOneWidget);
    expect(tester.widget<MenuItemButton>(item).onPressed, isNull);
    expect(asked?.pageIds, hasLength(3));
    await tester.tap(item, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(ran, 0);
  });

  testWidgets('one run at a time; an exception → reported + snack bar', (
    tester,
  ) async {
    final gate = Completer<void>();
    var slowRuns = 0;
    await pumpEditor(
      tester,
      overrides: [
        editorExtensionsProvider.overrideWithValue(
          EditorExtensions(
            moreMenuItems: [
              EditorMenuItem(
                id: 'test.slow',
                label: '느린 항목',
                icon: Icons.hourglass_empty,
                onSelected: (context, menu) async {
                  slowRuns++;
                  await gate.future;
                },
              ),
              EditorMenuItem(
                id: 'test.fail',
                label: '실패 항목',
                icon: Icons.error,
                onSelected: (context, menu) async =>
                    throw StateError('injected'),
              ),
            ],
          ),
        ),
      ],
    );
    await _openMore(tester);
    await _tapItem(tester, 'test.slow');
    await _openMore(tester);
    await _tapItem(tester, 'test.slow');
    expect(slowRuns, 1, reason: 'still running');
    gate.complete();
    await tester.pump();
    await _openMore(tester);
    await _tapItem(tester, 'test.slow');
    expect(slowRuns, 2);

    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    await _openMore(tester);
    await _tapItem(tester, 'test.fail');
    FlutterError.onError = previous;
    expect(reported.single.exception, isA<StateError>());
    expect(reported.single.library, 'feature_editor');
    expect(find.text(EditorStrings.commandFailed), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
