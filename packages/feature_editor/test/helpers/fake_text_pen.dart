// test/helpers/fake_text_pen.dart — (text pen, phase 1) a recording stand-in
// for recog's EditorTextPenSession: it records every call and converts the
// way recog does — ONE CompositeCommand([RemoveElements(group),
// AddObjects([a text box])], 'recog-text-pen') through the context's execute
// — with the text of [FakeTextPen.textFor] (null → no usable answer: convert
// opens the "sheet", i.e. calls fix).
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

final class FakeTextPenSession implements EditorTextPenSession {
  FakeTextPenSession(this.pen, this.context);

  final FakeTextPen pen;
  final EditorPenContext context;
  final List<String> calls = [];
  final List<EditorPenGroup> updates = [];
  final List<EditorPenGroup> converts = [];
  final List<EditorPenGroup> fixes = [];
  final ValueNotifier<int> _changes = ValueNotifier(0);
  bool disposed = false;
  int _ids = 0;

  @override
  void update(EditorPenGroup group) {
    calls.add('update ${group.strokes.length}');
    updates.add(group);
    _changes.value++;
  }

  @override
  void interrupt() => calls.add('interrupt');

  @override
  void clear() => calls.add('clear');

  bool _execute(EditorPenGroup group, String text) {
    final live = context.liveStrokes(group.pageId, [
      for (final s in group.strokes) s.id,
    ]);
    if (live == null) return false;
    final b = group.boundsPt;
    final box = core.TextBoxObject(
      id: 'fake-text-${++_ids}-${pen.sessions.length}',
      pageId: group.pageId,
      frame: core.ElementFrame(
        core.PageRect(b.left, b.top, b.left + 200, b.bottom),
      ),
      text: text,
      style: const core.TextBoxStyle(),
      createdAt: 9000 + _ids,
    );
    pen.converted.add(box);
    context.execute(
      core.CompositeCommand([
        core.RemoveElements(
          pageId: group.pageId,
          elementIds: [for (final s in live) s.id],
        ),
        core.AddObjects(pageId: group.pageId, objects: [box]),
      ], label: 'recog-text-pen'),
    );
    return true;
  }

  @override
  Future<bool> convert(EditorPenGroup group) async {
    calls.add('convert ${group.strokes.length}');
    converts.add(group);
    final hold = pen.holdConvert;
    if (hold != null) await hold.future;
    final text = pen.textFor(group);
    if (text == null) return fix(group);
    return _execute(group, text);
  }

  @override
  Future<bool> fix(EditorPenGroup group) async {
    calls.add('fix ${group.strokes.length}');
    fixes.add(group);
    final text = pen.sheetText;
    if (text == null) return false;
    return _execute(group, text);
  }

  @override
  Listenable get changes => _changes;

  @override
  Widget buildBubble(
    BuildContext context,
    EditorPenGroup group,
    VoidCallback onConvert,
    VoidCallback onFix,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'text bubble ${group.strokes.length}',
        key: const ValueKey('fake.textBubble'),
      ),
      TextButton(
        key: const ValueKey('fake.textBubble.fix'),
        onPressed: onFix,
        child: const Text('고치기'),
      ),
    ],
  );

  @override
  void dispose() {
    calls.add('dispose');
    disposed = true;
  }
}

final class FakeTextPen {
  /// The text a group converts to ('글 n' for n strokes by default).
  String? Function(EditorPenGroup group) textFor = (g) =>
      '글 ${g.strokes.length}';

  /// What the "sheet" (fix) converts to; null → the user cancels.
  String? sheetText;

  /// When set, convert waits for it.
  Completer<void>? holdConvert;

  final List<FakeTextPenSession> sessions = [];
  final List<core.TextBoxObject> converted = [];

  FakeTextPenSession get session => sessions.single;

  late final EditorTextPen slot = EditorTextPen(open: _open);

  EditorTextPenSession _open(EditorPenContext context) {
    final s = FakeTextPenSession(this, context);
    sessions.add(s);
    return s;
  }
}
