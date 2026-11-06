// m5-7/04-editor 8.2 E2-14, 6.14.4, 6.3.5 ② — memorization tapes through the
// whole editor (fake CORE, R2-B3 INK):
// - a finger tap (pen only) on a tape toggles it (INK toggleTape), no
//   command; a pen DOT (3 px, 150 ms) on a tape toggles it and leaves no dot
//   stroke; a 6 px short stroke or a drag on a tape is an ordinary stroke;
// - 테이프 모두 보이기 (more menu) reveals the tapes of every mounted page, of
//   a page mounted later and a tape drawn afterwards; 모두 가리기 covers them;
// - a per-tape toggle lives with its controller: a page that leaves the
//   mounted range and comes back, or a reopened note, shows it covered.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/document/page_mount.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const _penOnly = EditorSettings(inputMode: InputMode.penOnly);

/// A horizontal tape at [y] from x 100 to 400 (page pt).
core.Stroke _tape(String id, {double y = 300}) =>
    lineStroke(id: id, x0: 100, y0: y, x1: 400, y1: y, tool: core.PenTool.tape);

const _onTape = Offset(250, 300);

Future<EditorTestHandles> _pump(
  WidgetTester tester, {
  int pages = 3,
  Map<int, List<core.Stroke>>? strokes,
}) => pumpEditor(
  tester,
  pages: pages,
  settings: _penOnly,
  strokesByPageIndex:
      strokes ??
      {
        0: [_tape('tape-0')],
      },
);

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

PageMount _mount(EditorTestHandles h, int index) =>
    h.mountedPages[h.pageId(index)]!;

bool _revealed(EditorTestHandles h, int index, String id) =>
    _mount(h, index).controller.isTapeRevealed(id);

int _strokes(EditorTestHandles h, [int index = 0]) =>
    h.session.pageIfLoaded(h.pageId(index))!.strokes.length;

/// A one-finger tap at page point [at] after the palm rejection window.
Future<void> _fingerTap(
  WidgetTester tester,
  EditorTestHandles h,
  Offset at, {
  int page = 0,
}) async {
  await h.driver.wait(const Duration(seconds: 1));
  await h.driver.multiTap([h.toGlobal(page, at)]);
  await tester.pump();
}

/// A pen stroke from [at] (page 0 pt) by [by] SCREEN px, taking [duration].
Future<void> _pen(
  EditorTestHandles h,
  Offset at,
  Offset by, {
  Duration duration = const Duration(milliseconds: 150),
}) {
  final p = h.toGlobal(0, at);
  return h.driver.stylusStroke([
    p,
    p + by * 0.5,
    p + by,
  ], interval: duration ~/ 3);
}

Future<void> _jumpTo(
  WidgetTester tester,
  EditorTestHandles h,
  int index,
) async {
  await h.viewport.jumpToPage(index, animate: false);
  await tester.pump(const Duration(milliseconds: 200));
  await h.settlePages();
}

Future<void> _moreItem(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await tester.pump();
}

void main() {
  testWidgets('a finger tap on a tape → revealed, again → covered; no '
      'command; off the tape → nothing', (tester) async {
    final h = await _pump(tester);
    expect(_revealed(h, 0, 'tape-0'), isFalse);
    await _fingerTap(tester, h, _onTape);
    expect(_revealed(h, 0, 'tape-0'), isTrue);
    await _fingerTap(tester, h, _onTape);
    expect(_revealed(h, 0, 'tape-0'), isFalse);
    await _fingerTap(tester, h, const Offset(250, 500));
    expect(_revealed(h, 0, 'tape-0'), isFalse);
    expect(_edits(h), isEmpty);
    expect(h.session.history.undoDepth, 0);
  });

  testWidgets('a pen dot (3 px, 150 ms) on a tape → toggled, no dot stroke; a '
      '6 px short stroke and a drag → ordinary strokes, no toggle', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _pen(h, _onTape, const Offset(3, 0));
    await tester.pump();
    expect(_revealed(h, 0, 'tape-0'), isTrue);
    expect(_strokes(h), 1); // the tape only
    expect(_edits(h), isEmpty);

    await _pen(h, _onTape, const Offset(6, 0));
    await tester.pump();
    expect(_revealed(h, 0, 'tape-0'), isTrue); // not toggled
    expect(_strokes(h), 2);
    expect(_edits(h), ['execute:add-strokes']);

    await _pen(
      h,
      _onTape,
      const Offset(80, 10),
      duration: const Duration(milliseconds: 300),
    );
    await tester.pump();
    expect(_revealed(h, 0, 'tape-0'), isTrue);
    expect(_strokes(h), 3);
    // A dot away from any tape is a dot stroke.
    await _pen(h, const Offset(250, 600), const Offset(2, 0));
    await tester.pump();
    expect(_strokes(h), 4);
  });

  testWidgets('테이프 모두 보이기: every mounted page, a page mounted later and a '
      'tape drawn afterwards; 모두 가리기 covers them', (tester) async {
    final h = await _pump(
      tester,
      pages: 8,
      strokes: {
        0: [_tape('tape-0')],
        1: [_tape('tape-1')],
        6: [_tape('tape-6')],
      },
    );
    expect(h.mountedPages[h.pageId(6)], isNull); // not mounted yet
    await _moreItem(tester, EditorMoreMenu.tapesRevealAllKey);
    expect(_revealed(h, 0, 'tape-0'), isTrue);
    expect(_revealed(h, 1, 'tape-1'), isTrue);
    expect(_edits(h), isEmpty);

    await _jumpTo(tester, h, 6);
    expect(_revealed(h, 6, 'tape-6'), isTrue); // mounted later
    // A tape drawn now is revealed too.
    h.container
        .read(editorToolProvider.notifier)
        .selectPenType(core.PenTool.tape);
    await tester.pump();
    final before = {
      for (final s in h.session.pageIfLoaded(h.pageId(6))!.strokes) s.id,
    };
    await h.driver.stylusStroke([
      h.toGlobal(6, const Offset(100, 500)),
      h.toGlobal(6, const Offset(250, 500)),
      h.toGlobal(6, const Offset(400, 500)),
    ], interval: const Duration(milliseconds: 40));
    await tester.pump();
    final drawn = h.session
        .pageIfLoaded(h.pageId(6))!
        .strokes
        .where((s) => !before.contains(s.id))
        .single;
    expect(drawn.style.tool, core.PenTool.tape);
    expect(_revealed(h, 6, drawn.id), isTrue);

    await _moreItem(tester, EditorMoreMenu.tapesHideAllKey);
    expect(_revealed(h, 6, 'tape-6'), isFalse);
    expect(_revealed(h, 6, drawn.id), isFalse);
    await _jumpTo(tester, h, 0);
    expect(_revealed(h, 0, 'tape-0'), isFalse);
  });

  testWidgets('a per-tape toggle lives with its controller: out of the '
      'mounted range and back → covered; a reopened note → covered', (
    tester,
  ) async {
    final h = await _pump(tester, pages: 8);
    await _fingerTap(tester, h, _onTape);
    expect(_revealed(h, 0, 'tape-0'), isTrue);
    await _jumpTo(tester, h, 7);
    expect(h.mountedPages[h.pageId(0)], isNull); // left the range
    await _jumpTo(tester, h, 0);
    expect(_revealed(h, 0, 'tape-0'), isFalse);

    // Reopen the note: the same app tree, built again.
    await _fingerTap(tester, h, _onTape);
    expect(_revealed(h, 0, 'tape-0'), isTrue);
    final app = tester.widget<ProviderScope>(find.byType(ProviderScope).first);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(app);
    await tester.pump();
    await h.settlePages();
    expect(_revealed(h, 0, 'tape-0'), isFalse);
    expect(_edits(h), isEmpty);
  });
}
