// T26b (m5-7/03-ink 8.1, 4.10, 6.12.5): MathPreview — a valid formula lays out
// with a size > 0 (the real Math.tex), an invalid one has size 0 and calls onError
// once per (latex, message), after the frame and never during build.
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';

final _key = GlobalKey(debugLabel: 'preview');

Widget _app(String latex, {ValueChanged<String>? onError, bool ltr = true}) {
  final preview = Align(
    alignment: Alignment.topLeft,
    child: KeyedSubtree(
      key: _key,
      child: MathPreview(
        latex: latex,
        fontSize: 24,
        color: const Color(0xFF1A1A1A),
        onError: onError,
      ),
    ),
  );
  return ltr
      ? Directionality(textDirection: TextDirection.ltr, child: preview)
      : preview;
}

void main() {
  testWidgets('a valid formula has a size > 0', (tester) async {
    await tester.pumpWidget(_app(r'\frac{a}{b} + \sqrt{x^2}'));
    final size = tester.getSize(find.byKey(_key));
    expect(size.width, greaterThan(10));
    expect(size.height, greaterThan(10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('works without a Directionality ancestor', (tester) async {
    await tester.pumpWidget(_app('x^2', ltr: false));
    expect(tester.getSize(find.byKey(_key)).width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an invalid formula: size 0, onError once after the frame', (
    tester,
  ) async {
    final calls = <String>[];
    final phases = <SchedulerPhase>[];
    void onError(String m) {
      phases.add(SchedulerBinding.instance.schedulerPhase);
      calls.add(m);
    }

    await tester.pumpWidget(_app(r'\frac{a', onError: onError));
    expect(phases, [
      SchedulerPhase.postFrameCallbacks,
    ], reason: 'after the frame');
    expect(tester.getSize(find.byKey(_key)), Size.zero);
    expect(calls, ["Expected '}', got 'EOF'"]);
    // rebuilding with the same latex and a new callback instance: no new call
    await tester.pumpWidget(_app(r'\frac{a', onError: calls.add));
    await tester.pump();
    expect(calls, hasLength(1));
    // another error → one more call
    await tester.pumpWidget(_app(r'\foo', onError: calls.add));
    await tester.pump();
    expect(calls, hasLength(2));
    expect(calls.last, r'Undefined control sequence: \foo');
    // valid again, then the first error again → reported again
    await tester.pumpWidget(_app('x', onError: calls.add));
    await tester.pumpWidget(_app(r'\frac{a', onError: calls.add));
    await tester.pump();
    expect(calls, hasLength(3));
  });
}
