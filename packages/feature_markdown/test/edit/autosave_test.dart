// B-9 (08-markdown 8.7): 700 ms after the last keystroke, at least every 5 s while typing,
// a due save waits at most 1 s for an open IME composition.
import 'package:fake_async/fake_async.dart';
import 'package:feature_markdown/src/edit/autosave.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int saves;
  late bool composing;
  AutosaveScheduler make() =>
      AutosaveScheduler(onDue: () => saves++, isComposing: () => composing);

  setUp(() {
    saves = 0;
    composing = false;
  });

  test('700 ms after the last change', () {
    fakeAsync((async) {
      final s = make();
      s.changed();
      async.elapse(const Duration(milliseconds: 600));
      s.changed();
      async.elapse(const Duration(milliseconds: 600));
      expect(saves, 0);
      async.elapse(const Duration(milliseconds: 100));
      expect(saves, 1);
      expect(s.pending, isFalse);
      async.elapse(const Duration(seconds: 10));
      expect(saves, 1);
    });
  });

  test('at most every 5 s while typing goes on', () {
    fakeAsync((async) {
      final s = make();
      for (var i = 0; i < 60; i++) {
        s.changed();
        async.elapse(const Duration(milliseconds: 200));
      }
      // 12 s of typing → saves at 5 s and 10 s.
      expect(saves, 2);
      async.elapse(const Duration(seconds: 1));
      expect(saves, 3);
    });
  });

  test('an open composition delays a due save by at most 1 s', () {
    fakeAsync((async) {
      final s = make();
      composing = true;
      s.changed();
      async.elapse(const Duration(milliseconds: 700));
      expect(saves, 0);
      async.elapse(const Duration(milliseconds: 900));
      expect(saves, 0);
      async.elapse(const Duration(milliseconds: 200));
      expect(saves, 1, reason: 'saved after the 1 s grace, still composing');
    });
  });

  test('composition ending lets the save go at the next step', () {
    fakeAsync((async) {
      final s = make();
      composing = true;
      s.changed();
      async.elapse(const Duration(milliseconds: 800));
      composing = false;
      async.elapse(const Duration(milliseconds: 250));
      expect(saves, 1);
    });
  });

  test('cancel drops a scheduled save', () {
    fakeAsync((async) {
      final s = make()..changed();
      s.cancel();
      async.elapse(const Duration(seconds: 6));
      expect(saves, 0);
    });
  });
}
