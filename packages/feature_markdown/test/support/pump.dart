// Pumps the MD 문서 screen on the fake store (Track B tests).
import 'package:feature_markdown/feature_markdown.dart';
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

  static Future<MdHarness> create(WidgetTester tester) async {
    final store = createFakeNoteStore();
    addTearDown(() => tester.runAsync(store.close));
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
    String? query,
    List<Override> overrides = const [],
    double textScale = 1,
    bool settle = true,
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
          ),
        ),
      ),
    );
    if (settle) await settleMd(tester);
  }
}

/// A few frames (the view never stops animating while a snack bar shows, so no
/// pumpAndSettle).
Future<void> settleMd(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
