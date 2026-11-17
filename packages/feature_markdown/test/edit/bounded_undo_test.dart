// MD-T19 (08-markdown 8.7 U4): the editor's undo history is capped (entries and UTF-16
// units), groups typing within 500 ms, keeps programmatic changes as single steps, and
// starts again after another device's change (review A2).
import 'package:fake_async/fake_async.dart';
import 'package:feature_markdown/src/edit/bounded_undo.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _v(String s) => TextEditingValue(
  text: s,
  selection: TextSelection.collapsed(offset: s.length),
);

void main() {
  test('typing within 500 ms is one step; a pause starts the next', () {
    fakeAsync((async) {
      final h = BoundedUndoHistory()..reset(_v(''));
      h.record(_v('a'));
      async.elapse(const Duration(milliseconds: 100));
      h.record(_v('ab'));
      async.elapse(const Duration(milliseconds: 600));
      h.record(_v('abc'));
      expect(h.length, 3);
      expect(h.undo()!.text, 'ab');
      expect(h.undo()!.text, '');
      expect(h.undo(), isNull);
      expect(h.redo()!.text, 'ab');
      expect(h.redo()!.text, 'abc');
      expect(h.canRedo, isFalse);
      h.dispose();
    });
  });

  test('a single change is its own step; a new edit drops the redo steps', () {
    fakeAsync((async) {
      final h = BoundedUndoHistory()..reset(_v('- [ ] a'));
      h.record(_v('- [x] a'), single: true);
      h.record(_v('- [x] ab'));
      expect(h.length, 3);
      expect(h.undo()!.text, '- [x] a');
      h.record(_v('- [x] az'));
      expect(h.canRedo, isFalse);
      expect(h.undo()!.text, '- [x] a');
      expect(h.undo()!.text, '- [ ] a');
      h.dispose();
    });
  });

  test('at most 200 entries', () {
    fakeAsync((async) {
      final h = BoundedUndoHistory()..reset(_v(''));
      for (var i = 0; i < 500; i++) {
        h.record(_v('x' * (i + 1)), single: true);
      }
      expect(h.length, 200);
      var steps = 0;
      while (h.undo() != null) {
        steps++;
      }
      expect(steps, 199);
      h.dispose();
    });
  });

  test('at most 4,000,000 units: a 150,000-unit document keeps ~26 states', () {
    fakeAsync((async) {
      final h = BoundedUndoHistory()..reset(_v('가' * 150000));
      for (var i = 0; i < 100; i++) {
        h.record(_v('${'가' * 150000}$i'), single: true);
        expect(h.units, lessThanOrEqualTo(4000000 + 150010));
      }
      expect(h.units, lessThanOrEqualTo(4000000));
      expect(h.length, inInclusiveRange(20, 27));
      h.dispose();
    });
  });

  test('reset (another device) forgets every step', () {
    fakeAsync((async) {
      final h = BoundedUndoHistory()..reset(_v('a'));
      h.record(_v('ab'));
      expect(h.value.canUndo, isTrue);
      h.reset(_v('다른 기기'));
      expect(h.value.canUndo, isFalse);
      expect(h.undo(), isNull);
      h.dispose();
    });
  });
}
