// test/helpers/fake_math_pen.dart — (math pen, phase 1) a recording stand-in
// for recog's EditorMathPenSession: it records every call and converts the
// way recog does — ONE CompositeCommand([RemoveElements(group),
// AddObjects([math with the group as ink])]) through the context's execute
// — with the LaTeX of [FakeMathPen.latexFor] (null → no usable result:
// nothing converts).
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

final class FakeMathPenSession implements EditorMathPenSession {
  FakeMathPenSession(this.pen, this.context);

  final FakeMathPen pen;
  final EditorMathPenContext context;
  final List<String> calls = [];
  final List<EditorMathGroup> updates = [];
  final List<(EditorMathGroup, EditorMathConvertTrigger)> converts = [];
  final List<core.MathObject> fixes = [];
  final ValueNotifier<int> _changes = ValueNotifier(0);
  bool disposed = false;
  int _ids = 0;

  @override
  void update(EditorMathGroup group) {
    calls.add('update ${group.strokes.length}');
    updates.add(group);
    _changes.value++;
  }

  @override
  void interrupt() => calls.add('interrupt');

  @override
  void clear() => calls.add('clear');

  @override
  Future<bool> convert(
    EditorMathGroup group,
    EditorMathConvertTrigger trigger,
  ) async {
    calls.add('convert ${trigger.name}');
    converts.add((group, trigger));
    final hold = pen.holdConvert;
    if (hold != null) await hold.future;
    final latex = pen.latexFor(group);
    if (latex == null) return false;
    final live = context.liveStrokes(group.pageId, [
      for (final s in group.strokes) s.id,
    ]);
    if (live == null) return false;
    final b = group.boundsPt;
    final math = core.MathObject(
      id: 'fake-math-${++_ids}-${pen.sessions.length}',
      pageId: group.pageId,
      frame: core.ElementFrame(
        core.PageRect(b.left, b.top, b.left + b.height * 2, b.bottom),
      ),
      latex: latex,
      style: const core.MathStyle(),
      engineId: 'fake/1',
      ink: [for (final s in live) s.copyWith(pageId: group.pageId)],
      createdAt: 9000 + _ids,
    );
    pen.converted.add(math);
    context.execute(
      core.CompositeCommand([
        core.RemoveElements(
          pageId: group.pageId,
          elementIds: [for (final s in live) s.id],
        ),
        core.AddObjects(pageId: group.pageId, objects: [math]),
      ], label: 'recog-math-pen'),
    );
    return true;
  }

  @override
  Future<void> fix(core.MathObject math) async {
    calls.add('fix ${math.id}');
    fixes.add(math);
  }

  @override
  Listenable get changes => _changes;

  @override
  Widget buildBubble(
    BuildContext context,
    EditorMathGroup group,
    VoidCallback onConvert,
  ) => Text(
    'bubble ${group.strokes.length}',
    key: const ValueKey('fake.bubble'),
  );

  @override
  void dispose() {
    calls.add('dispose');
    disposed = true;
  }
}

final class FakeMathPen {
  /// The LaTeX a group converts to ('x^{n}' for n strokes by default).
  String? Function(EditorMathGroup group) latexFor = (g) =>
      'x^{${g.strokes.length}}';

  /// When set, convert waits for it.
  Completer<void>? holdConvert;

  final List<FakeMathPenSession> sessions = [];
  final List<core.MathObject> converted = [];

  FakeMathPenSession get session => sessions.single;

  late final EditorMathPen slot = EditorMathPen(open: _open);

  EditorMathPenSession _open(EditorMathPenContext context) {
    final s = FakeMathPenSession(this, context);
    sessions.add(s);
    return s;
  }
}
