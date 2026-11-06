// m5-7/04-editor 8.2 E2-06, 6.6.2: selectionPriority — every row of the
// table (5 tools × 5 origins × handle / body / outside = 75 cases), written
// out row by row and compared with the function.
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/selection_priority.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _h = SelectionPriority.handle;
const _m = SelectionPriority.move;
const _d = SelectionPriority.drop;

/// The 6.6.2 table as written: body column per (tool, origin) —
/// lasso, paste, insert, drawn, tap.
const Map<EditorTool, List<SelectionPriority>> _body = {
  EditorTool.lasso: [_m, _m, _m, _m, _m],
  EditorTool.pen: [_m, _m, _m, _d, _d],
  EditorTool.eraser: [_m, _m, _m, _d, _d],
  EditorTool.shape: [_m, _m, _m, _d, _d],
  EditorTool.text: [_m, _m, _m, _d, _d],
};

const List<SelectionOrigin> _origins = [
  SelectionOrigin.lasso,
  SelectionOrigin.paste,
  SelectionOrigin.insert,
  SelectionOrigin.drawn,
  SelectionOrigin.tap,
];

void main() {
  test('the table covers every tool and origin', () {
    expect(_body.keys.toSet(), EditorTool.values.toSet());
    expect(_origins.toSet(), SelectionOrigin.values.toSet());
  });

  for (final tool in EditorTool.values) {
    for (var i = 0; i < _origins.length; i++) {
      final origin = _origins[i];
      test('$tool × $origin: handle → handle, body → ${_body[tool]![i].name}, '
          'outside → drop', () {
        expect(selectionPriority(origin, tool, SelectionHitKind.handle), _h);
        expect(
          selectionPriority(origin, tool, SelectionHitKind.body),
          _body[tool]![i],
        );
        expect(selectionPriority(origin, tool, SelectionHitKind.outside), _d);
      });
    }
  }

  test('bodyMoves: lasso, paste, insert yes; drawn, tap no', () {
    expect(
      {for (final o in SelectionOrigin.values) o: bodyMoves(o)},
      {
        SelectionOrigin.lasso: true,
        SelectionOrigin.paste: true,
        SelectionOrigin.insert: true,
        SelectionOrigin.drawn: false,
        SelectionOrigin.tap: false,
      },
    );
  });
}
