// E-07: ToolState / ToolController (04-editor 6.6.1, stored forms 6.14) on the
// fake store with fake_async: defaults = core.StrokeStyle.defaultsFor, eraser
// switch and return, per-type styles, normalized values, the three pressure
// curves, highlighter straightening on the highlighter only, the three keys
// (editor.penStyles / editor.eraser synced, editor.toolSelection device)
// written 500 ms after a change and restored in a new container, P1 styles
// round trip, remote synced values, invalid stored entries.
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/pen/width_mapping.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../helpers/settings_env.dart';

const _ms = Duration(milliseconds: 1);
const _debounce = Duration(milliseconds: 500);
final _styles = EditorSettingKeys.penStyles;
final _eraser = EditorSettingKeys.eraser;
final _selection = EditorSettingKeys.toolSelection;

extension on SettingsEnv {
  ToolController get tools => container.read(editorToolProvider.notifier);
  ToolState get toolState => container.read(editorToolProvider);

  /// Starts the tool controller and lets its load finish.
  void loadTools() {
    container.listen(editorToolProvider, (_, _) {});
    async.flushMicrotasks();
  }

  /// A second app run on the same store: a new container, loaded.
  ToolState restoredToolState() {
    final other = ProviderContainer(
      overrides: [core.noteStoreProvider.overrideWithValue(store)],
    );
    final sub = other.listen(editorToolProvider, (_, _) {});
    async.flushMicrotasks();
    final restored = other.read(editorToolProvider);
    expect(other.read(editorToolProvider.notifier).isLoaded, isTrue);
    sub.close();
    other.dispose();
    async.flushMicrotasks();
    return restored;
  }
}

void main() {
  test('defaults: pen, ballpoint, every tool at StrokeStyle.defaultsFor', () {
    runSettingsEnv((env) {
      env.loadTools();
      final s = env.toolState;
      expect(s.activeTool, EditorTool.pen);
      expect(s.penType, core.PenTool.ballpoint);
      expect(s.previousTool, isNull);
      expect(s.eyedropperActive, isFalse);
      expect(s.eraser, const EraserSettings());
      expect(s.penStyles.keys, unorderedEquals(core.PenTool.values));
      for (final t in core.PenTool.values) {
        expect(s.penStyles[t], core.StrokeStyle.defaultsFor(t), reason: '$t');
      }
      expect(
        s.currentPen,
        core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      );
      expect(
        () => s.penStyles[core.PenTool.pencil] = s.currentPen,
        throwsUnsupportedError,
      );
      expect(env.settings.writes, isEmpty, reason: 'loading writes nothing');
    });
  });

  test('switching to the eraser remembers the previous tool; '
      'returnFromEraser goes back', () {
    runSettingsEnv((env) {
      env.loadTools();
      final tools = env.tools;
      tools.selectTool(EditorTool.lasso);
      tools.selectTool(EditorTool.eraser);
      expect(env.toolState.activeTool, EditorTool.eraser);
      expect(env.toolState.previousTool, EditorTool.lasso);
      tools.returnFromEraser();
      expect(env.toolState.activeTool, EditorTool.lasso);
      expect(env.toolState.previousTool, isNull);

      tools.selectPenType(core.PenTool.marker);
      tools.selectTool(EditorTool.eraser);
      expect(env.toolState.previousTool, EditorTool.pen);
      tools.selectTool(EditorTool.eraser); // again: no change
      expect(env.toolState.previousTool, EditorTool.pen);
      tools.returnFromEraser();
      expect(env.toolState.activeTool, EditorTool.pen);
      expect(env.toolState.penType, core.PenTool.marker);

      // Not on the eraser: no-op. Leaving the eraser by hand clears previous.
      tools.returnFromEraser();
      expect(env.toolState.activeTool, EditorTool.pen);
      tools.selectTool(EditorTool.eraser);
      tools.selectTool(EditorTool.lasso);
      expect(env.toolState.previousTool, isNull);
      tools.selectTool(EditorTool.eraser);
      expect(env.toolState.previousTool, EditorTool.lasso);
      tools.selectPenType(core.PenTool.pencil);
      expect(env.toolState.activeTool, EditorTool.pen);
      expect(env.toolState.previousTool, isNull);
    });
  });

  test('each pen type keeps its own style', () {
    runSettingsEnv((env) {
      env.loadTools();
      final tools = env.tools;
      tools.selectPenType(core.PenTool.fountain);
      tools.setColor(0xFF0000FF);
      tools.setWidth(3.3);
      tools.selectPenType(core.PenTool.ballpoint);
      expect(
        env.toolState.currentPen,
        core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      );
      tools.setColor(0xFF00FF00);
      tools.selectPenType(core.PenTool.fountain);
      final fountain = env.toolState.currentPen;
      expect(fountain.tool, core.PenTool.fountain);
      expect(fountain.colorArgb, 0xFF0000FF);
      expect(fountain.width, 3.3);
      expect(
        env.toolState.penStyles[core.PenTool.ballpoint]!.colorArgb,
        0xFF00FF00,
      );

      // updateStyleOf edits a tool that is not active (settings > pen).
      tools.updateStyleOf(
        core.PenTool.pencil,
        (s) => s.copyWith(width: 4, tool: core.PenTool.marker),
      );
      final pencil = env.toolState.penStyles[core.PenTool.pencil]!;
      expect(pencil.tool, core.PenTool.pencil, reason: 'tool kept');
      expect(pencil.width, 4);
      expect(env.toolState.penType, core.PenTool.fountain);
    });
  });

  test('values are normalized: alpha 0xFF, ranges and steps', () {
    runSettingsEnv((env) {
      env.loadTools();
      final tools = env.tools;
      core.StrokeStyle pen() => env.toolState.currentPen;

      tools.setColor(0x80FF0000);
      expect(pen().colorArgb, 0xFFFF0000);
      tools.setOpacity(0.01);
      expect(pen().opacity, core.StrokeStyle.minOpacity);
      tools.setOpacity(1.7);
      expect(pen().opacity, 1);
      tools.setOpacity(0.456);
      expect(pen().opacity, 0.46);
      tools.setWidth(100);
      expect(pen().width, WidthMapping.max);
      tools.setWidth(0);
      expect(pen().width, WidthMapping.min);
      tools.setWidth(2.34);
      expect(pen().width, 2.3);
      tools.setPressureSensitivity(0.73);
      expect(pen().pressureSensitivity, 0.75);
      tools.setPressureSensitivity(3);
      expect(pen().pressureSensitivity, 1);
      tools.setSmoothing(-1);
      expect(pen().smoothing, 0);
      tools.setSmoothing(0.62);
      expect(pen().smoothing, 0.6);

      tools.applyStyle(
        const core.StrokeStyle(
          tool: core.PenTool.marker,
          colorArgb: 0x11223344,
          width: 99,
          opacity: 0,
        ),
      );
      expect(env.toolState.penType, core.PenTool.marker);
      expect(env.toolState.activeTool, EditorTool.pen);
      expect(pen(), pen().normalized());
      expect(pen().colorArgb, 0xFF223344);
      expect(pen().width, core.StrokeStyle.maxWidth);
      expect(pen().opacity, core.StrokeStyle.minOpacity);

      tools.updateEraser((e) => e.copyWith(diameter: 7.3));
      expect(env.toolState.eraser.diameter, 7.5);
      tools.updateEraser((e) => e.copyWith(diameter: 1000));
      expect(env.toolState.eraser.diameter, EraserSettings.maxDiameter);
      tools.updateEraser((e) => e.copyWith(diameter: 0));
      expect(env.toolState.eraser.diameter, EraserSettings.minDiameter);
    });
  });

  test('the three pressure curves', () {
    runSettingsEnv((env) {
      env.loadTools();
      for (final curve in [
        core.PressureCurve.soft,
        core.PressureCurve.linear,
        core.PressureCurve.firm,
      ]) {
        env.tools.setPressureCurve(curve);
        expect(env.toolState.currentPen.pressureCurve, curve);
      }
      env.tools.setPressureCurve(core.PressureCurve.soft);
      env.async.elapse(_debounce);
      final stored = env.storedValue(_styles)['styles']! as Map;
      expect(
        (stored['ballpoint'] as Map)['pressureCurve'],
        core.PressureCurve.soft.toJson(),
      );
    });
  });

  test('highlighter straightening applies to the highlighter only', () {
    runSettingsEnv((env) {
      env.loadTools();
      final before = env.toolState;
      env.tools.setHighlighterStraightening(
        ink.HighlighterStraightening.alwaysStraight,
      );
      expect(env.toolState, before, reason: 'ballpoint active: no-op');

      env.tools.selectPenType(core.PenTool.highlighter);
      env.tools.setHighlighterStraightening(
        ink.HighlighterStraightening.snapOnLift,
      );
      final hl = env.toolState.currentPen;
      expect(
        hl.highlighterStraightening,
        ink.HighlighterStraightening.snapOnLift,
      );
      expect(hl.extras['hlStraight'], 'snapOnLift');
      expect(env.toolState.penStyles[core.PenTool.ballpoint]!.extras, isEmpty);
    });
  });

  test('EraserSettings: toSpec radius = diameter / 2, JSON round trip', () {
    const e = EraserSettings(
      mode: ink.EraserMode.stroke,
      diameter: 20,
      filter: core.StrokeFilter.highlighterOnly,
      returnToPreviousTool: true,
    );
    expect(
      e.toSpec(),
      const ink.EraserSpec(
        mode: ink.EraserMode.stroke,
        radius: 10,
        filter: core.StrokeFilter.highlighterOnly,
      ),
    );
    expect(e.toJson(), {
      'v': 1,
      'mode': 'stroke',
      'diameter': 20.0,
      'filter': 'highlighterOnly',
      'returnToPrevious': true,
    });
    expect(EraserSettings.fromJson(e.toJson()), e);
    expect(const EraserSettings().toJson(), {
      'v': 1,
      'mode': 'partial',
      'diameter': 12.0,
      'filter': 'all',
      'returnToPrevious': false,
    });
    final invalid = <String>[];
    expect(
      EraserSettings.fromJson({
        'v': 3,
        'mode': 'zap',
        'diameter': 500,
        'filter': 7,
        'returnToPrevious': 'yes',
      }, invalidFields: invalid),
      const EraserSettings(),
    );
    expect(invalid, ['mode', 'diameter', 'filter', 'returnToPrevious']);
  });

  test('changes are written 500 ms later, one key each, and restored in a new '
      'container', () {
    runSettingsEnv((env) {
      env.loadTools();
      final tools = env.tools;
      tools.selectPenType(core.PenTool.fountain);
      env.async.elapse(_debounce);
      expect(env.settings.writesOf(_selection.name), hasLength(1));
      expect(env.settings.writesOf(_styles.name), isEmpty);
      expect(env.settings.writesOf(_eraser.name), isEmpty);

      // A burst on one style writes penStyles once.
      tools
        ..setColor(0xFF112233)
        ..setWidth(4.4)
        ..setOpacity(0.8);
      env.async.elapse(_debounce - _ms);
      expect(env.settings.writesOf(_styles.name), isEmpty);
      env.async.elapse(_ms);
      expect(env.settings.writesOf(_styles.name), hasLength(1));
      expect(env.settings.writesOf(_selection.name), hasLength(1));

      tools.updateEraser(
        (e) => e.copyWith(
          mode: ink.EraserMode.stroke,
          diameter: 30,
          filter: core.StrokeFilter.exceptHighlighter,
          returnToPreviousTool: true,
        ),
      );
      tools.selectTool(EditorTool.eraser);
      tools.setEyedropper(true);
      env.async.elapse(_debounce);
      expect(env.settings.writesOf(_eraser.name), hasLength(1));
      expect(env.settings.writesOf(_styles.name), hasLength(1));

      expect(env.storedValue(_selection), {
        'v': 1,
        'activeTool': 'eraser',
        'penType': 'fountain',
        'previousTool': 'pen',
      });
      expect(env.storedValue(_eraser), {
        'v': 1,
        'mode': 'stroke',
        'diameter': 30.0,
        'filter': 'exceptHighlighter',
        'returnToPrevious': true,
      });
      final stored = env.storedValue(_styles);
      expect(stored['v'], 1);
      final styles = stored['styles']! as Map;
      expect(
        styles.keys,
        unorderedEquals([for (final t in core.PenTool.values) t.wireName]),
      );
      expect(
        styles['fountain'],
        env.toolState.penStyles[core.PenTool.fountain]!.toJson(),
      );
      expect(_styles.scope, core.SettingScope.synced);
      expect(_eraser.scope, core.SettingScope.synced);
      expect(_selection.scope, core.SettingScope.device);

      final restored = env.restoredToolState();
      expect(restored, env.toolState.copyWith(eyedropperActive: false));
      expect(restored.eyedropperActive, isFalse, reason: 'never stored');
    });
  });

  test('a P1 tool style round-trips (stored, restored, extras kept)', () {
    runSettingsEnv((env) {
      env.loadTools();
      const calligraphy = core.StrokeStyle(
        tool: core.PenTool.calligraphy,
        colorArgb: 0xFF336699,
        width: 4,
        extras: {'nibAngleDeg': 30},
      );
      env.tools.applyStyle(calligraphy);
      expect(env.toolState.penType, core.PenTool.calligraphy);
      expect(env.toolState.currentPen, calligraphy);
      env.async.elapse(_debounce);
      final restored = env.restoredToolState();
      expect(restored.penType, core.PenTool.calligraphy);
      expect(restored.penStyles[core.PenTool.calligraphy], calligraphy);
      expect(
        restored.penStyles[core.PenTool.tape],
        core.StrokeStyle.defaultsFor(core.PenTool.tape),
      );
    });
  });

  test('resetPenDefaults restores every tool and is stored', () {
    runSettingsEnv((env) {
      env.loadTools();
      env.tools
        ..setColor(0xFF445566)
        ..selectPenType(core.PenTool.pencil)
        ..setWidth(9);
      env.async.elapse(_debounce);
      env.tools.resetPenDefaults();
      expect(env.toolState.penStyles, ToolState.defaultPenStyles());
      expect(env.toolState.penType, core.PenTool.pencil, reason: 'kept');
      env.async.elapse(_debounce);
      expect(env.restoredToolState().penStyles, ToolState.defaultPenStyles());
    });
  });

  test('stored values replace the defaults after the load; a change before '
      'the load wins for its key', () {
    runSettingsEnv((env) {
      final hl = core.StrokeStyle.defaultsFor(core.PenTool.highlighter)
          .copyWith(colorArgb: 0xFF00FFAA);
      env.storeValue(_styles, {
        'v': 1,
        'styles': {'highlighter': hl.toJson()},
      });
      env.storeValue(_selection, {
        'v': 1,
        'activeTool': 'lasso',
        'penType': 'highlighter',
        'previousTool': null,
      });
      env.storeValue(_eraser, const EraserSettings(diameter: 40).toJson());

      env.container.listen(editorToolProvider, (_, _) {});
      expect(env.toolState, ToolState.defaults(), reason: 'synchronous build');
      // Before the load completes: the eraser change wins.
      env.tools.updateEraser((e) => e.copyWith(diameter: 5));
      env.async.flushMicrotasks();
      expect(env.tools.isLoaded, isTrue);
      expect(env.toolState.activeTool, EditorTool.lasso);
      expect(env.toolState.penType, core.PenTool.highlighter);
      expect(env.toolState.currentPen, hl);
      expect(env.toolState.eraser.diameter, 5);
      env.async.elapse(_debounce);
      expect(env.storedValue(_eraser)['diameter'], 5.0);
    });
  });

  test('remote synced values are applied; our own echo is ignored', () {
    runSettingsEnv((env) {
      env.loadTools();
      env.tools.setColor(0xFF010203);
      env.async.elapse(_debounce);
      final mine = env.toolState;
      env.async.flushMicrotasks();
      expect(env.toolState, mine, reason: 'own echo');

      // Another device (M4) changes the marker and the eraser.
      final marker = core.StrokeStyle.defaultsFor(core.PenTool.marker)
          .copyWith(width: 8);
      final remoteStyles = {
        'v': 1,
        'styles': {
          for (final e in mine.penStyles.entries)
            e.key.wireName: e.value.toJson(),
          'marker': marker.toJson(),
        },
      };
      env.storeValue(_styles, remoteStyles);
      expect(env.toolState.penStyles[core.PenTool.marker], marker);
      expect(env.toolState.currentPen.colorArgb, 0xFF010203);
      env.storeValue(_eraser, const EraserSettings(diameter: 50).toJson());
      expect(env.toolState.eraser.diameter, 50);
      expect(
        env.settings.writesOf(_styles.name),
        hasLength(1),
        reason: 'applying a remote value does not write it back',
      );
      env.async.elapse(const Duration(seconds: 2));
      expect(env.settings.writesOf(_eraser.name), isEmpty);
    });
  });

  test('invalid stored entries → defaults, reported once', () {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    runSettingsEnv((env) {
      env.storeValue(_styles, {
        'v': 1,
        'styles': {
          'ballpoint': {'tool': 'ballpoint', 'color': 'red', 'width': 1},
          'fountain': core.StrokeStyle.defaultsFor(core.PenTool.marker)
              .toJson(),
          'pencil': 3,
          'quill': {'tool': 'quill'}, // a newer tool: skipped, not an error
        },
      });
      env.storeValue(_selection, {
        'v': 1,
        'activeTool': 'wand',
        'penType': 'quill',
        'previousTool': 'pen',
      });
      env.storeValue(_eraser, {'v': 1, 'mode': 'zap', 'diameter': 3});
      env.loadTools();
      expect(reported, hasLength(1));
      expect(reported.single.library, 'feature_editor');
      final message = '${reported.single.exception}';
      for (final path in [
        'editor.penStyles.styles.ballpoint',
        'editor.penStyles.styles.fountain',
        'editor.penStyles.styles.pencil',
        'editor.toolSelection.activeTool',
        'editor.toolSelection.penType',
        'editor.eraser.mode',
      ]) {
        expect(message, contains(path));
      }
      expect(message, isNot(contains('quill')));
      final s = env.toolState;
      expect(s.penStyles, ToolState.defaultPenStyles());
      expect(s.activeTool, EditorTool.pen);
      expect(s.previousTool, isNull, reason: 'only kept with the eraser');
      expect(s.penType, core.PenTool.ballpoint);
      expect(s.eraser, const EraserSettings(diameter: 3));
    });
  });

  test('the eyedropper is transient: not stored, ended by a tool change', () {
    runSettingsEnv((env) {
      env.loadTools();
      env.tools.setEyedropper(true);
      expect(env.toolState.eyedropperActive, isTrue);
      env.async.elapse(_debounce);
      expect(env.settings.writes, isEmpty);
      env.tools.selectTool(EditorTool.pen);
      expect(env.toolState.eyedropperActive, isFalse);
      env.tools.setEyedropper(true);
      env.tools.selectTool(EditorTool.lasso);
      expect(env.toolState.eyedropperActive, isFalse);
    });
  });

  test('flush writes pending keys at once', () {
    runSettingsEnv((env) {
      env.loadTools();
      env.tools
        ..setWidth(5)
        ..selectTool(EditorTool.lasso);
      var done = false;
      env.tools.flush().then((_) => done = true);
      env.async.flushMicrotasks();
      expect(done, isTrue);
      expect(env.settings.writesOf(_styles.name), hasLength(1));
      expect(env.settings.writesOf(_selection.name), hasLength(1));
    });
  });
}
