// EditorSettings model and its stored JSON form (04-editor 4.8, 6.14;
// contract 7.2.17 / 7.4.6). Foundation step B5 ships the model with JSON;
// task E-06 adds the notifier's load / save tests next to this file.
import 'dart:convert';

import 'package:feature_editor/feature_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

const _custom = EditorSettings(
  inputMode: InputMode.fingerDrawing,
  palmRejection: PalmRejectionSettings(
    penCooldown: Duration(milliseconds: 650),
    treatHoverAsPenActivity: false,
    maxTouchRadius: 72.5,
  ),
  gestures: GestureSettings(
    twoFingerTapUndo: false,
    threeFingerTapRedo: true,
    longPressMenu: false,
  ),
  pageFlipMode: PageFlipMode.horizontalPaged,
  pressureMode: ink.PressureMode.alwaysSimulated,
  showDevOverlay: true,
  stylusSeen: true,
);

/// Round trip through a JSON string, as CORE stores it.
Map<String, Object?> _viaJsonString(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  group('toJson', () {
    test('device key has exactly the 6.14 fields, "v" first', () {
      expect(
        const EditorSettings().toJson(core.SettingScope.device),
        <String, Object?>{
          'v': 1,
          'inputMode': 'auto',
          'palm': {'cooldownMs': 400, 'hover': true, 'maxRadius': 45.0},
          'pressure': 'auto',
          'dev': false,
          'stylusSeen': false,
        },
      );
      expect(
        const EditorSettings().toJson(core.SettingScope.device).keys.first,
        'v',
      );
    });

    test('synced key has exactly the 6.14 fields, "v" first', () {
      final json = const EditorSettings().toJson(core.SettingScope.synced);
      expect(json, <String, Object?>{
        'v': 1,
        'gestures': {
          'twoFingerUndo': true,
          'threeFingerRedo': true,
          'longPressMenu': true,
        },
        'pageFlip': 'verticalScroll',
      });
      expect(json.keys.first, 'v');
    });

    test('device and synced fields do not overlap (contract 7.4.6 scopes)', () {
      final device = _custom.toJson(core.SettingScope.device).keys.toSet();
      final synced = _custom.toJson(core.SettingScope.synced).keys.toSet();
      expect(device.intersection(synced), {'v'});
    });

    test('the pressure mode is stored by its INK name', () {
      for (final mode in ink.PressureMode.values) {
        final json = const EditorSettings()
            .copyWith(pressureMode: mode)
            .toJson(core.SettingScope.device);
        expect(json['pressure'], mode.name);
      }
    });
  });

  group('fromJson', () {
    test('round trip through JSON text keeps every field', () {
      final back = EditorSettings.fromJson(
        device: _viaJsonString(_custom.toJson(core.SettingScope.device)),
        synced: _viaJsonString(_custom.toJson(core.SettingScope.synced)),
      );
      expect(back, _custom);
    });

    test('each scope restores only its own fields', () {
      final deviceOnly = EditorSettings.fromJson(
        device: _custom.toJson(core.SettingScope.device),
      );
      expect(deviceOnly.inputMode, _custom.inputMode);
      expect(deviceOnly.palmRejection, _custom.palmRejection);
      expect(deviceOnly.pressureMode, _custom.pressureMode);
      expect(deviceOnly.showDevOverlay, isTrue);
      expect(deviceOnly.stylusSeen, isTrue);
      expect(deviceOnly.gestures, const GestureSettings());
      expect(deviceOnly.pageFlipMode, PageFlipMode.verticalScroll);

      final syncedOnly = EditorSettings.fromJson(
        synced: _custom.toJson(core.SettingScope.synced),
      );
      expect(syncedOnly.gestures, _custom.gestures);
      expect(syncedOnly.pageFlipMode, _custom.pageFlipMode);
      expect(syncedOnly.inputMode, InputMode.auto);
      expect(syncedOnly.palmRejection, const PalmRejectionSettings());
    });

    test('empty maps give the defaults', () {
      expect(EditorSettings.fromJson(), const EditorSettings());
    });

    test('unknown keys are ignored and a newer "v" is still read', () {
      final back = EditorSettings.fromJson(
        device: {
          'v': 7,
          'inputMode': 'penOnly',
          'future': {'a': 1},
          'palm': {'cooldownMs': 0, 'extra': true},
        },
        synced: {'v': 2, 'pageFlip': 'horizontalPaged', 'other': 'x'},
      );
      expect(back.inputMode, InputMode.penOnly);
      expect(back.palmRejection.penCooldown, Duration.zero);
      expect(back.pageFlipMode, PageFlipMode.horizontalPaged);
    });

    test('invalid values fall back to the defaults, field by field', () {
      final back = EditorSettings.fromJson(
        device: {
          'inputMode': 'stylus', // unknown name
          'palm': {
            'cooldownMs': 1550, // > 1500
            'hover': 'yes', // not a bool
            'maxRadius': 10, // < 20
          },
          'pressure': 3, // not a string
          'dev': 1, // not a bool
          'stylusSeen': null,
        },
        synced: {
          'gestures': ['twoFingerUndo'], // not an object
          'pageFlip': 'VERTICALSCROLL', // names are case-sensitive
        },
      );
      expect(back, const EditorSettings());
    });

    test('a valid field survives next to invalid ones', () {
      final back = EditorSettings.fromJson(
        device: {
          'inputMode': 'nope',
          'palm': {'cooldownMs': -50, 'hover': false, 'maxRadius': 'big'},
          'dev': true,
        },
        synced: {
          'gestures': {'twoFingerUndo': 0, 'longPressMenu': false},
        },
      );
      expect(back.inputMode, InputMode.auto);
      expect(
        back.palmRejection,
        const PalmRejectionSettings(treatHoverAsPenActivity: false),
      );
      expect(back.showDevOverlay, isTrue);
      expect(back.gestures, const GestureSettings(longPressMenu: false));
    });

    test('pressure accepts the draft values always / never', () {
      ink.PressureMode read(Object? value) =>
          EditorSettings.fromJson(device: {'pressure': value}).pressureMode;
      expect(read('auto'), ink.PressureMode.auto);
      expect(read('alwaysReal'), ink.PressureMode.alwaysReal);
      expect(read('alwaysSimulated'), ink.PressureMode.alwaysSimulated);
      expect(read('always'), ink.PressureMode.alwaysReal);
      expect(read('never'), ink.PressureMode.alwaysSimulated);
      expect(read('sometimes'), ink.PressureMode.auto);
      expect(read(null), ink.PressureMode.auto);
    });

    test('number fields accept ints and doubles (contract 7.4.6)', () {
      final palm = PalmRejectionSettings.fromJson({
        'cooldownMs': 500.0,
        'maxRadius': 60, // web jsonEncode(60.0) writes 60
      });
      expect(palm.penCooldown, const Duration(milliseconds: 500));
      expect(palm.maxTouchRadius, 60.0);
      expect(palm.maxTouchRadius, isA<double>());
    });

    test('range limits are inclusive; NaN and infinity are invalid', () {
      expect(
        PalmRejectionSettings.fromJson({'cooldownMs': 1500, 'maxRadius': 20}),
        const PalmRejectionSettings(
          penCooldown: Duration(milliseconds: 1500),
          maxTouchRadius: 20,
        ),
      );
      expect(
        PalmRejectionSettings.fromJson({'maxRadius': 120.0}).maxTouchRadius,
        120.0,
      );
      expect(
        PalmRejectionSettings.fromJson({
          'cooldownMs': double.nan,
          'maxRadius': double.infinity,
        }),
        const PalmRejectionSettings(),
      );
      expect(
        PalmRejectionSettings.fromJson({'maxRadius': 120.5}).maxTouchRadius,
        45.0,
      );
    });

    test('a nested map with non-string keys keeps its string keys', () {
      final back = EditorSettings.fromJson(
        synced: {
          'gestures': <Object?, Object?>{1: false, 'longPressMenu': false},
        },
      );
      expect(back.gestures, const GestureSettings(longPressMenu: false));
    });
  });

  group('value semantics', () {
    test('== and hashCode follow every field', () {
      expect(_custom, _custom.copyWith());
      expect(_custom.hashCode, _custom.copyWith().hashCode);
      final variants = <EditorSettings>[
        _custom.copyWith(inputMode: InputMode.auto),
        _custom.copyWith(
          palmRejection: _custom.palmRejection.copyWith(
            penCooldown: Duration.zero,
          ),
        ),
        _custom.copyWith(
          palmRejection: _custom.palmRejection.copyWith(
            treatHoverAsPenActivity: true,
          ),
        ),
        _custom.copyWith(
          palmRejection: _custom.palmRejection.copyWith(maxTouchRadius: 45),
        ),
        _custom.copyWith(
          gestures: _custom.gestures.copyWith(twoFingerTapUndo: true),
        ),
        _custom.copyWith(
          gestures: _custom.gestures.copyWith(threeFingerTapRedo: false),
        ),
        _custom.copyWith(
          gestures: _custom.gestures.copyWith(longPressMenu: true),
        ),
        _custom.copyWith(pageFlipMode: PageFlipMode.verticalScroll),
        _custom.copyWith(pressureMode: ink.PressureMode.auto),
        _custom.copyWith(showDevOverlay: false),
        _custom.copyWith(stylusSeen: false),
      ];
      for (final variant in variants) {
        expect(variant, isNot(_custom), reason: '$variant');
      }
    });

    test('copyWith without arguments keeps the values', () {
      expect(_custom.palmRejection.copyWith(), _custom.palmRejection);
      expect(_custom.gestures.copyWith(), _custom.gestures);
    });
  });

  test('isPenOnlyEffective table (04-editor 4.8)', () {
    final cases = <(InputMode, bool), bool>{
      (InputMode.auto, false): false,
      (InputMode.auto, true): true,
      (InputMode.penOnly, false): true,
      (InputMode.penOnly, true): true,
      (InputMode.fingerDrawing, false): false,
      (InputMode.fingerDrawing, true): false,
    };
    cases.forEach((input, expected) {
      final settings = EditorSettings(
        inputMode: input.$1,
        stylusSeen: input.$2,
      );
      expect(settings.isPenOnlyEffective, expected, reason: '$input');
    });
  });
}
