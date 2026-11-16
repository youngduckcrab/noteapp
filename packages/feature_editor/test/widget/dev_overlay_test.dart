// E-19: the developer overlay (04-editor 6.12): turned on by the setting,
// the more menu, ⌘/Ctrl+Shift+D or the URL flag → ink.inkDiagnosticsProvider
// enabled and DevMetrics running; hidden (or the editor gone) → both stop.
// Shows the INK snapshot (FakeInkClock), the EDITOR values, the CORE storage
// line (lastCommitLatency) and devOverlaySectionsProvider sections, whose
// line changes show up (listened only while visible).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/ui/dev/dev_metrics.dart';
import 'package:feature_editor/src/ui/dev/dev_overlay.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// Section lines that count their listeners.
class _CountingLines extends ValueNotifier<List<String>> {
  _CountingLines(super.value);
  int listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }
}

String _overlayText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(DevOverlay.overlayKey),
        matching: find.byType(Text),
      ),
    )
    .data!;

/// Pumps until the INK snapshot stops changing, then long enough for the
/// overlay to show it. INK keeps reporting after a commit — it rasterizes the
/// committed stroke's tiles in later frames and reports the cache then — and
/// notifies at most every 250 ms (03-ink 4.12, trailing edge included); the
/// overlay rebuilds at most [DevOverlay.refreshInterval] after a notification.
Future<ink.InkStatsSnapshot> _settledInkSnapshot(
  WidgetTester tester,
  ink.InkDiagnostics diagnostics,
) async {
  const step = Duration(milliseconds: 300);
  var last = diagnostics.snapshot;
  for (var i = 0; i < 20; i++) {
    await tester.pump(step);
    final now = diagnostics.snapshot;
    if (now == last) break;
    last = now;
  }
  // INK's trailing notification (≤ 250 ms) + the overlay's refresh timer.
  await tester.pump(step);
  await tester.pump(step);
  expect(diagnostics.snapshot, last, reason: 'INK snapshot did not settle');
  return last;
}

/// Overlay shown, INK collecting, DevMetrics running — or none of them.
void _expectOn(WidgetTester tester, EditorTestHandles h, bool on) {
  expect(find.byKey(DevOverlay.overlayKey), on ? findsOneWidget : findsNothing);
  expect(h.container.read(ink.inkDiagnosticsProvider).enabled, on);
  expect(h.container.read(editorDevMetricsProvider).isRunning, on);
}

void main() {
  testWidgets('off by default; the setting, the more menu and Ctrl+Shift+D '
      'turn it on and off', (tester) async {
    // (v2.14-ui) ⋯ '개발자 표시' needs developer mode.
    final h = await pumpEditor(
      tester,
      overrides: [core.developerModeProvider.overrideWithValue(true)],
    );
    _expectOn(tester, h, false);

    // The more menu item.
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(EditorMoreMenu.devOverlayKey));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    _expectOn(tester, h, true);
    expect(h.container.read(editorSettingsProvider).showDevOverlay, isTrue);

    // The shortcut.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    _expectOn(tester, h, false);

    // The setting itself.
    h.container.read(editorSettingsProvider.notifier).toggleDevOverlay();
    await tester.pump();
    _expectOn(tester, h, true);
    h.container.read(editorSettingsProvider.notifier).toggleDevOverlay();
    await tester.pump();
    _expectOn(tester, h, false);
    await tester.pump(const Duration(seconds: 1)); // settings write
  });

  testWidgets('the URL flag shows it with the setting off; leaving the '
      'editor stops collecting', (tester) async {
    final h = await pumpEditor(
      tester,
      overrides: [editorDevUrlFlagProvider.overrideWithValue(true)],
    );
    expect(h.container.read(editorSettingsProvider).showDevOverlay, isFalse);
    _expectOn(tester, h, true);
    final diagnostics = h.container.read(ink.inkDiagnosticsProvider);
    final metrics = h.container.read(editorDevMetricsProvider);

    await tester.pumpWidget(const SizedBox());
    expect(diagnostics.enabled, isFalse);
    expect(metrics.isRunning, isFalse);
  });

  testWidgets('INK snapshot (FakeInkClock), EDITOR values and the storage '
      'line', (tester) async {
    final clock = ink_testing.FakeInkClock();
    final h = await pumpEditor(
      tester,
      settings: const EditorSettings(showDevOverlay: true),
      overrides: [ink.inkClockProvider.overrideWithValue(clock)],
    );
    _expectOn(tester, h, true);
    await h.driver.stylusStroke(
      pathThrough(h, 0, const [
        Offset(100, 100),
        Offset(160, 130),
        Offset(220, 150),
      ]),
    );
    final diagnostics = h.container.read(ink.inkDiagnosticsProvider);
    final snapshot = await _settledInkSnapshot(tester, diagnostics);
    expect(snapshot.lastKind, ink.InkPointerKind.stylus);
    expect(snapshot.eventToPaint.count, greaterThan(0));
    expect(snapshot.visibleStrokeCount, 1);
    final metrics = h.container.read(editorDevMetricsProvider).snapshot;
    expect(metrics.lastKind, PointerDeviceKind.stylus);
    expect(metrics.lastStrokePoints, greaterThan(0));
    expect(metrics.currentPageStrokes, 1);
    expect(metrics.currentPage, 1);
    expect(metrics.zoom, closeTo(1, 1e-9));
    expect(metrics.visibleRangeLabel, isNot('-'));
    expect(metrics.inputModeLabel, endsWith('(auto)'));

    final text = _overlayText(tester);
    for (final line in devInkLines(snapshot)) {
      expect(text, contains(line));
    }
    for (final line in devEditorLines(metrics)) {
      expect(text, contains(line));
    }
    final status = h.container.read(core.persistenceStatusProvider).value;
    expect(
      text,
      contains(
        devStorageLine(h.container.read(core.storageInfoProvider), status),
      ),
    );
    expect(text, contains('[저장] nativeFile'));
  });

  testWidgets('a palm rejected while the overlay runs is counted', (
    tester,
  ) async {
    final h = await pumpEditor(
      tester,
      settings: const EditorSettings(showDevOverlay: true),
    );
    final at = pageCenterOf(h, 0);
    // Stylus down, then a finger lands while the pen draws (P4 → rejected).
    await h.driver.down(1, at, kind: PointerDeviceKind.stylus);
    await h.driver.move(1, at + const Offset(20, 10));
    await h.driver.down(2, at + const Offset(200, 200));
    await h.driver.up(2);
    await h.driver.up(1);
    await tester.pump(const Duration(milliseconds: 300));
    final metrics = h.container.read(editorDevMetricsProvider).snapshot;
    expect(metrics.palmRejectedCount, greaterThanOrEqualTo(1));
    expect(_overlayText(tester), contains('팜 거부 ${metrics.palmRejectedCount}'));
  });

  testWidgets('sections: shown after the EDITOR blocks, line changes show up, '
      'listened only while visible', (tester) async {
    final lines = _CountingLines(['pages 3', 'cache 1.0MB']);
    addTearDown(lines.dispose);
    final h = await pumpEditor(
      tester,
      settings: const EditorSettings(showDevOverlay: true),
      overrides: [
        devOverlaySectionsProvider.overrideWithValue([
          DevOverlaySection(id: 'pdf', title: 'PDF 렌더', lines: lines),
        ]),
      ],
    );
    await tester.pump(const Duration(milliseconds: 300));
    var text = _overlayText(tester);
    expect(text, contains('[PDF 렌더]'));
    expect(text, contains('pages 3'));
    expect(text.indexOf('[PDF 렌더]'), greaterThan(text.indexOf('[저장]')));
    expect(lines.listeners, greaterThan(0));

    lines.value = ['pages 4'];
    await tester.pump(const Duration(milliseconds: 300));
    text = _overlayText(tester);
    expect(text, contains('pages 4'));
    expect(text, isNot(contains('cache 1.0MB')));

    h.container.read(editorCommandsProvider).toggleDevOverlay();
    await tester.pump();
    expect(find.byKey(DevOverlay.overlayKey), findsNothing);
    expect(lines.listeners, 0);
    await tester.pump(const Duration(seconds: 1));
  });
}
