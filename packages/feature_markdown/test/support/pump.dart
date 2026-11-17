// Pumps the MD 문서 screen on the fake store (Track B tests).
import 'package:feature_markdown/feature_markdown.dart';
import 'package:feature_markdown/src/markdown_screen.dart'
    show kMarkdownLiveHintSetting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:ui_kit/ui_kit.dart';

final class MdHarness {
  MdHarness(this.store);

  final NoteStore store;
  int closed = 0;
  int openedAsNote = 0;
  final List<NoteId> openedMarkdown = [];

  /// [hint]: the one-time '글을 누르면 바로 고칠 수 있어요' snack bar may still show (off by
  /// default, so it covers nothing in the other tests).
  static Future<MdHarness> create(
    WidgetTester tester, {
    bool hint = false,
  }) async {
    final store = createFakeNoteStore();
    addTearDown(() => tester.runAsync(store.close));
    if (!hint) {
      await tester.runAsync(
        () => store.settings.set(kMarkdownLiveHintSetting, true),
      );
    }
    return MdHarness(store);
  }

  Future<NoteId> doc(
    WidgetTester tester,
    String text, {
    String title = 'T',
  }) async => (await tester.runAsync(
    () => store.markdown.create(title: title, text: text),
  ))!.id;

  Future<String> stored(WidgetTester tester, NoteId id) async =>
      (await tester.runAsync(() => store.markdown.get(id)))!.text;

  Future<void> pump(
    WidgetTester tester,
    NoteId id, {
    Size size = const Size(1194, 834),
    AppStyle style = AppStyle.craft,
    Brightness brightness = Brightness.light,
    bool initialEdit = false,
    bool source = false,
    String? query,
    List<Override> overrides = const [],
    double textScale = 1,
    bool settle = true,
    bool canOpenMarkdown = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteStoreProvider.overrideWithValue(store), ...overrides],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildStyleTheme(style, brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: MarkdownScreen(
            key: ValueKey('md-$id-$initialEdit-$query'),
            noteId: id,
            initialEdit: initialEdit,
            initialQuery: query,
            onClose: () => closed++,
            onOpenAsNote: () => openedAsNote++,
            onOpenMarkdown: canOpenMarkdown ? openedMarkdown.add : null,
          ),
        ),
      ),
    );
    if (settle || source) await settleMd(tester);
    if (source) {
      // 원문 (the whole-source editor; 보기 edits block by block since v2.18-md).
      await tester.tap(find.byKey(MarkdownKeys.mode));
      await settleMd(tester);
    }
  }
}

/// A few frames (the view never stops animating while a snack bar shows, so no
/// pumpAndSettle).
Future<void> settleMd(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
