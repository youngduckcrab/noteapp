// E2-03 (m5-7/04-editor 6.2.4, 6.2.2, 6.18): ToolOptions — the shape and
// text tool defaults — and its notifier on the fake store under fake_async.
// - JSON round trip (toJson → JSON text → fromJson);
// - invalid values → defaults: an unknown ShapeKind → rectangle and unknown
//   enum names in the styles → that field's default, unreported; wrong types
//   → defaults with one report;
// - the arrow rule: arrow + arrowHeads none → end (a line keeps none);
// - polygon sides clamped to 3..12, star points to 4..16;
// - synced key editor.toolOptions written 500 ms after the last change,
//   restored in a new container, a change before the load wins, a remote
//   value followed.
import 'dart:convert';

import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/tool_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/settings_env.dart';

const _ms = Duration(milliseconds: 1);
const _debounce = Duration(milliseconds: 500);
final _key = EditorSettingKeys.toolOptions;

extension on SettingsEnv {
  ToolOptionsNotifier get options =>
      container.read(editorToolOptionsProvider.notifier);
  ToolOptions get optionsState => container.read(editorToolOptionsProvider);

  void loadOptions() {
    container.listen(editorToolOptionsProvider, (_, _) {});
    async.flushMicrotasks();
  }

  ToolOptions restoredOptions() {
    final other = ProviderContainer(
      overrides: [core.noteStoreProvider.overrideWithValue(store)],
    );
    final sub = other.listen(editorToolOptionsProvider, (_, _) {});
    async.flushMicrotasks();
    final restored = other.read(editorToolOptionsProvider);
    expect(other.read(editorToolOptionsProvider.notifier).isLoaded, isTrue);
    sub.close();
    other.dispose();
    async.flushMicrotasks();
    return restored;
  }
}

List<FlutterErrorDetails> _captureReports() {
  final reported = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reported.add;
  addTearDown(() => FlutterError.onError = previous);
  return reported;
}

void main() {
  const custom = ToolOptions(
    shapeKind: core.ShapeKind.star,
    shapeStyle: core.ShapeStyle(
      strokeColorArgb: 0xFF2244AA,
      strokeWidth: 3.5,
      dash: core.LineDash.dashed,
      fillColorArgb: 0xFFFFEE00,
      fillOpacity: 0.5,
    ),
    polygonSides: 7,
    starPoints: 9,
    textStyle: core.TextBoxStyle(
      fontSizePt: 24,
      colorArgb: 0xFF990000,
      bold: true,
      align: core.TextAlignKind.center,
      backgroundArgb: 0x40FFFF00,
    ),
  );

  test('defaults and toJson form', () {
    const d = ToolOptions();
    expect(d.shapeKind, core.ShapeKind.rectangle);
    expect(d.shapeStyle, const core.ShapeStyle(strokeColorArgb: 0xFF1A1A1A));
    expect(d.polygonSides, 5);
    expect(d.starPoints, 5);
    expect(d.textStyle, const core.TextBoxStyle());
    final json = d.toJson();
    expect(json.keys, ['v', 'shape', 'text']);
    expect(json['v'], 1);
    expect((json['shape']! as Map).keys, ['kind', 'style', 'sides', 'points']);
    expect((json['shape']! as Map)['kind'], 'rectangle');
    expect(json['text'], const core.TextBoxStyle().toJson());
  });

  test('JSON round trip through JSON text', () {
    for (final o in [const ToolOptions(), custom.normalized()]) {
      final text = jsonEncode(o.toJson());
      final back = ToolOptions.fromJson(
        (jsonDecode(text) as Map).cast<String, Object?>(),
      );
      expect(back, o);
      expect(back.hashCode, o.hashCode);
    }
  });

  test('unknown names → defaults, unreported', () {
    final invalid = <String>[];
    final o = ToolOptions.fromJson({
      'v': 1,
      'shape': {
        'kind': 'heart',
        'style': {
          'strokeColorArgb': 0xFF00AA00,
          'dash': 'wavy',
          'arrowHeads': 'triple',
        },
        'sides': 6,
      },
      'text': {'fontSizePt': 20, 'align': 'justify'},
    }, invalidFields: invalid);
    expect(invalid, isEmpty);
    expect(o.shapeKind, core.ShapeKind.rectangle);
    expect(o.shapeStyle.strokeColorArgb, 0xFF00AA00, reason: 'kept');
    expect(o.shapeStyle.dash, core.LineDash.solid);
    expect(o.shapeStyle.arrowHeads, core.ArrowHeads.none);
    expect(o.polygonSides, 6);
    expect(o.textStyle.fontSizePt, 20);
    expect(o.textStyle.align, core.TextAlignKind.start);
  });

  test('wrong types → defaults, listed as invalid', () {
    final invalid = <String>[];
    final o = ToolOptions.fromJson({
      'shape': {
        'kind': 3,
        'style': {'strokeColorArgb': 'red'},
        'sides': 'six',
        'points': 4.5,
      },
      'text': 'big',
    }, invalidFields: invalid);
    expect(o, const ToolOptions());
    expect(invalid, [
      'shape.kind',
      'shape.style',
      'text',
      'shape.sides',
      'shape.points',
    ]);
    expect(
      ToolOptions.fromJson({'shape': 'x'}, invalidFields: invalid),
      const ToolOptions(),
    );
    expect(invalid.last, 'shape');
  });

  test('arrow rule: arrow with arrowHeads none → end; a line keeps none', () {
    final arrow = const ToolOptions(shapeKind: core.ShapeKind.arrow)
        .normalized();
    expect(arrow.shapeStyle.arrowHeads, core.ArrowHeads.end);
    const both = ToolOptions(
      shapeKind: core.ShapeKind.arrow,
      shapeStyle: core.ShapeStyle(
        strokeColorArgb: 0xFF000000,
        arrowHeads: core.ArrowHeads.both,
      ),
    );
    expect(both.normalized().shapeStyle.arrowHeads, core.ArrowHeads.both);
    final line = const ToolOptions(shapeKind: core.ShapeKind.line).normalized();
    expect(line.shapeStyle.arrowHeads, core.ArrowHeads.none);
    // Read back the same way.
    expect(
      ToolOptions.fromJson({
        'shape': {'kind': 'arrow'},
      }).shapeStyle.arrowHeads,
      core.ArrowHeads.end,
    );
  });

  test('sides 3..12 and points 4..16 clamped', () {
    for (final (sides, expected) in [(1, 3), (3, 3), (12, 12), (40, 12)]) {
      expect(
        ToolOptions(polygonSides: sides).normalized().polygonSides,
        expected,
      );
      expect(
        ToolOptions.fromJson({
          'shape': {'sides': sides},
        }).polygonSides,
        expected,
      );
    }
    for (final (points, expected) in [(2, 4), (16, 16), (99, 16)]) {
      expect(ToolOptions(starPoints: points).normalized().starPoints, expected);
    }
    expect(
      2 * ToolOptions.maxStarPoints <= core.PageObjectLimits.maxPolylinePoints,
      isTrue,
    );
  });

  test(
    'notifier: synced key written 500 ms after the last change, restored',
    () {
      expect(_key.scope, core.SettingScope.synced);
      runSettingsEnv((env) {
        env.loadOptions();
        expect(env.optionsState, const ToolOptions());
        expect(env.settings.writes, isEmpty, reason: 'loading writes nothing');
        env.options
          ..setShapeKind(core.ShapeKind.arrow)
          ..setPolygonSides(20)
          ..setStarPoints(8)
          ..setTextStyle(const core.TextBoxStyle(fontSizePt: 30, bold: true));
        final s = env.optionsState;
        expect(s.shapeStyle.arrowHeads, core.ArrowHeads.end);
        expect(s.polygonSides, 12);
        env.async.elapse(_debounce - _ms);
        expect(env.settings.writesOf(_key.name), isEmpty);
        env.async.elapse(_ms);
        expect(env.settings.writesOf(_key.name), hasLength(1));
        expect(env.storedValue(_key), s.toJson());
        expect(env.restoredOptions(), s);
      });
    },
  );

  test('notifier: invalid stored value → defaults, one report; a change '
      'before the load wins', () {
    final reported = _captureReports();
    runSettingsEnv((env) {
      env.storeValue(_key, {
        'v': 1,
        'shape': {'kind': 9},
      });
      env.loadOptions();
      expect(env.optionsState, const ToolOptions());
      expect(reported, hasLength(1));
      expect(
        '${reported.single.exception}',
        contains('editor.toolOptions.shape.kind'),
      );
    });
    runSettingsEnv((env) {
      env.storeValue(_key, custom.toJson());
      env.container.listen(editorToolOptionsProvider, (_, _) {});
      env.options.setShapeKind(core.ShapeKind.ellipse);
      env.async.flushMicrotasks();
      expect(env.optionsState.shapeKind, core.ShapeKind.ellipse);
      expect(env.optionsState.starPoints, 5, reason: 'the stored value lost');
      env.async.elapse(_debounce);
    });
  });

  test('notifier: a remote value is followed, its own echo ignored', () {
    runSettingsEnv((env) {
      env.loadOptions();
      env.options.setShapeKind(core.ShapeKind.triangle);
      env.async.elapse(_debounce);
      expect(env.optionsState.shapeKind, core.ShapeKind.triangle);
      env.storeValue(_key, custom.toJson());
      env.async.flushMicrotasks();
      expect(env.optionsState, custom.normalized());
    });
  });
}
