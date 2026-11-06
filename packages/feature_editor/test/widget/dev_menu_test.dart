// E-19: the more menu's 개발자 메뉴 (04-editor 6.12.4, EDITOR-S1): only while
// the developer overlay is visible; 합성 노트 만들기 → one more note in the
// fake store + snack bar; 합성 획 1,000 → current page +1,000 strokes as one
// undo step (one undo removes them); disabled on a read-only note; 진단
// 초기화 → the counters back to zero.
// (v2, E2-20 — m5-7/04-editor 6.20) 도형 표본 모으기: off → a stroke keeps
// no sample; on (the menu's check item → EditorDeviceState) → each pen
// session's points (page pt), viewScale and result, newest first; 도형 표본
// 복사 → the sample sheet → the expected kind sheet → LIBRARY's text
// {kind, points, viewScale} on the clipboard + '도형 표본을 복사했어요'; no
// sample → '모은 표본이 없어요'; 텍스트 상자 시험 is offered, 텍스트 입력
// 방식 only on the web.
import 'dart:convert';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/tools/shape_samples.dart';
import 'package:feature_editor/src/ui/dev/dev_metrics.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/toolbar/dev_menu.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

const _devOn = EditorSettings(showDevOverlay: true);

Future<void> _openDevMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(EditorDevMenu.menuKey));
  await tester.pumpAndSettle();
}

/// Taps a MenuItemButton (onPressed runs after the next frame).
Future<void> _pick(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shown only while the overlay is visible', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(EditorDevMenu.menuKey), findsNothing);
    await tester.tap(find.byKey(EditorMoreMenu.devOverlayKey));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(EditorDevMenu.menuKey), findsOneWidget);
    await tester.tap(find.byKey(EditorDevMenu.menuKey));
    await tester.pumpAndSettle();
    expect(find.text(EditorStrings.syntheticStrokes(1000)), findsOneWidget);
    expect(find.text('현재 페이지에 합성 획 3,000개'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('합성 노트 만들기 → a note in the store + snack bar', (tester) async {
    final h = await pumpEditor(tester, settings: _devOn);
    await _openDevMenu(tester);
    await _pick(tester, EditorDevMenu.seedNoteKey);
    for (var i = 0; i < 400; i++) {
      if (find
          .text(EditorStrings.seedSyntheticNoteDone)
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text(EditorStrings.seedSyntheticNoteDone), findsOneWidget);
    final found = await h.store.library.searchLibrary('perf-test');
    expect(found.notes.single.title, 'perf-test');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1)); // the snack bar
    }
  });

  testWidgets('합성 획 1,000 → current page +1,000, one undo step', (
    tester,
  ) async {
    final h = await pumpEditor(tester, settings: _devOn);
    final id = h.pageId(0);
    final before = h.session.pageIfLoaded(id)!.strokeCount;
    final depth = h.session.history.undoDepth;
    h.recorder!.clearCalls();
    await _openDevMenu(tester);
    await _pick(tester, EditorDevMenu.strokesKey(1000));
    await tester.pump();
    expect(h.recorder!.calls, contains('executeAsync:add-strokes'));
    expect(h.session.pageIfLoaded(id)!.strokeCount, before + 1000);
    expect(h.session.history.undoDepth, depth + 1);

    final undo = h.container.read(editorCommandsProvider).undo();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await undo;
    expect(h.session.pageIfLoaded(id)!.strokeCount, before);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('read only: the stroke items are disabled, the others are not', (
    tester,
  ) async {
    final h = await pumpEditor(tester, settings: _devOn);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    await _openDevMenu(tester);
    for (final n in EditorDevMenu.strokeCounts) {
      expect(
        tester
            .widget<MenuItemButton>(find.byKey(EditorDevMenu.strokesKey(n)))
            .onPressed,
        isNull,
      );
    }
    expect(
      tester
          .widget<MenuItemButton>(find.byKey(EditorDevMenu.seedNoteKey))
          .onPressed,
      isNotNull,
    );
    // The command refuses too.
    h.recorder!.clearCalls();
    await h.container.read(editorCommandsProvider).addSyntheticStrokes(10);
    expect(h.recorder!.calls.where((c) => c.contains('add-strokes')), isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('진단 초기화 → the DevMetrics counters back to zero', (tester) async {
    final h = await pumpEditor(tester, settings: _devOn);
    final metrics = h.container.read(editorDevMetricsProvider)
      ..recordPalmRejected()
      ..recordStrokeCommitted(pointCount: 50);
    await tester.pump(const Duration(milliseconds: 300));
    expect(metrics.snapshot.palmRejectedCount, 1);
    await _openDevMenu(tester);
    await _pick(tester, EditorDevMenu.resetKey);
    await tester.pump(const Duration(milliseconds: 300));
    expect(metrics.snapshot.palmRejectedCount, 0);
    expect(metrics.snapshot.lastStrokePoints, 0);
  });

  group('v2 (E2-20)', () {
    tearDown(() => TextEditNotifier.debugIsWebOverride = null);

    /// The recorded clipboard texts (Clipboard.setData).
    List<String?> mockClipboard(WidgetTester tester) {
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return copied;
    }

    Future<void> drawLine(EditorTestHandles h, double y) =>
        h.driver.stylusStroke([
          for (var i = 0; i <= 8; i++) h.toGlobal(0, Offset(100.0 + i * 20, y)),
        ]);

    testWidgets('도형 표본 모으기 off (default) → no sample; on → each pen '
        'session, newest first', (tester) async {
      final h = await pumpEditor(tester, settings: _devOn);
      final samples = h.container.read(editorShapeSamplesProvider);
      expect(
        h.container.read(editorDeviceStateProvider).collectShapeSamples,
        isFalse,
      );
      await drawLine(h, 150);
      await tester.pump();
      expect(samples.samples, isEmpty);

      await _openDevMenu(tester);
      // CheckboxMenuButton hands its key to the MenuItemButton it builds.
      final toggle = find.byType(CheckboxMenuButton);
      expect(
        tester.widget<CheckboxMenuButton>(toggle).key,
        EditorDevMenu.collectShapeSamplesKey,
      );
      expect(tester.widget<CheckboxMenuButton>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        h.container.read(editorDeviceStateProvider).collectShapeSamples,
        isTrue,
      );

      await drawLine(h, 200);
      await drawLine(h, 260);
      await tester.pump();
      expect(samples.samples, hasLength(2));
      final newest = samples.samples.first;
      expect(newest.result, 'stroke');
      // down + 8 moves + up, in page pt along y = 260.
      expect(newest.points, hasLength(10));
      expect(newest.points.first.dx, closeTo(100, 0.5));
      expect(newest.points.first.dy, closeTo(260, 0.5));
      expect(newest.points.last.dx, closeTo(260, 0.5));
      expect(newest.viewScale, closeTo(h.viewport.camera.scale, 1e-9));
      expect(samples.samples.last.points.first.dy, closeTo(200, 0.5));
      // Six more sessions: only the last 5 stay.
      for (var i = 0; i < 6; i++) {
        await drawLine(h, 300.0 + i * 20);
      }
      await tester.pump();
      expect(samples.samples, hasLength(ShapeSamples.capacity));
      expect(samples.samples.first.points.first.dy, closeTo(400, 0.5));
    });

    testWidgets('도형 표본 복사 → sample sheet → 기대 종류 → LIBRARY text on '
        'the clipboard + snack bar', (tester) async {
      final copied = mockClipboard(tester);
      final h = await pumpEditor(tester, settings: _devOn);
      h.container
          .read(editorDeviceStateProvider.notifier)
          .setCollectShapeSamples(true);
      await tester.pump();
      await drawLine(h, 150);
      await drawLine(h, 220);
      await tester.pump();

      await _openDevMenu(tester);
      await _pick(tester, EditorDevMenu.copyShapeSampleKey);
      await tester.pumpAndSettle();
      // Newest first: 1. is the y = 220 stroke.
      expect(find.byKey(EditorDevMenu.shapeSampleKey(0)), findsOneWidget);
      expect(find.byKey(EditorDevMenu.shapeSampleKey(1)), findsOneWidget);
      expect(find.text('1. stroke'), findsOneWidget);
      await tester.tap(find.byKey(EditorDevMenu.shapeSampleKey(0)));
      await tester.pumpAndSettle();
      expect(find.text(EditorStrings.devExpectedShape), findsOneWidget);
      for (final kind in core.ShapeKind.values) {
        expect(
          find.byKey(EditorDevMenu.expectedShapeKey(kind)),
          findsOneWidget,
        );
      }
      expect(find.text(EditorStrings.devNotAShape), findsOneWidget);
      await tester.tap(
        find.byKey(EditorDevMenu.expectedShapeKey(core.ShapeKind.rectangle)),
      );
      await tester.pumpAndSettle();

      expect(copied, hasLength(1));
      final json = jsonDecode(copied.single!) as Map<String, Object?>;
      expect(json.keys, ['kind', 'points', 'viewScale']);
      expect(json['kind'], 'rectangle');
      final points = json['points']! as List<Object?>;
      expect(points, hasLength(10));
      final first = points.first! as List<Object?>;
      expect(first, hasLength(2));
      expect(first[0] as num, closeTo(100, 0.5));
      expect(first[1] as num, closeTo(220, 0.5));
      expect(json['viewScale'] as num, closeTo(h.viewport.camera.scale, 1e-9));
      expect(find.text(EditorStrings.devShapeSampleCopied), findsOneWidget);
    });

    testWidgets('도형 아님(글씨) → kind none; no sample → 모은 표본이 없어요, '
        'nothing copied', (tester) async {
      final copied = mockClipboard(tester);
      final h = await pumpEditor(tester, settings: _devOn);
      await _openDevMenu(tester);
      await _pick(tester, EditorDevMenu.copyShapeSampleKey);
      await tester.pumpAndSettle();
      expect(find.text(EditorStrings.devNoShapeSamples), findsOneWidget);
      expect(find.byKey(EditorDevMenu.shapeSampleKey(0)), findsNothing);
      expect(copied, isEmpty);

      h.container
          .read(editorDeviceStateProvider.notifier)
          .setCollectShapeSamples(true);
      await tester.pump();
      await drawLine(h, 150);
      await tester.pump();
      await _openDevMenu(tester);
      await _pick(tester, EditorDevMenu.copyShapeSampleKey);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EditorDevMenu.shapeSampleKey(0)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EditorDevMenu.expectedShapeKey(null)));
      await tester.pumpAndSettle();
      expect(copied, hasLength(1));
      expect((jsonDecode(copied.single!) as Map)['kind'], 'none');
    });

    testWidgets('텍스트 상자 시험 is offered; 텍스트 입력 방식 only on the web', (
      tester,
    ) async {
      await pumpEditor(tester, settings: _devOn);
      await _openDevMenu(tester);
      expect(find.byKey(EditorDevMenu.textBoxProbeKey), findsOneWidget);
      expect(find.byKey(EditorDevMenu.textInputModeKey), findsNothing);
      expect(find.byKey(EditorDevMenu.collectShapeSamplesKey), findsWidgets);
      expect(find.byKey(EditorDevMenu.copyShapeSampleKey), findsOneWidget);
    });

    testWidgets('on the web: 텍스트 입력 방식 is offered too', (tester) async {
      TextEditNotifier.debugIsWebOverride = true;
      await pumpEditor(tester, settings: _devOn);
      await _openDevMenu(tester);
      expect(find.byKey(EditorDevMenu.textInputModeKey), findsOneWidget);
    });
  });
}
