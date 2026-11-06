// GestureSettings v2 (2nd-round contract m5-7/00-overview 7.2.10, EDITOR
// details m5-7/04-editor 4.3.2; task R2-B5, 8.1): the 7-row default / allowed
// table, actionFor's three steps, reading v1.4 JSON, the actions round trip,
// unknown / disallowed values dropped silently, withAction (default removes
// the explicit entry, except for a gesture whose v1.4 bool was false) and
// toJson's bools = action != none.
import 'dart:convert';

import 'package:feature_editor/feature_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// The contract 7.2.10 table: gesture → (default, allowed actions).
const _table = <EditorGesture, (EditorAction, Set<EditorAction>)>{
  EditorGesture.twoFingerTap: (
    EditorAction.undo,
    {
      EditorAction.none,
      EditorAction.undo,
      EditorAction.redo,
      EditorAction.toggleEraser,
    },
  ),
  EditorGesture.threeFingerTap: (
    EditorAction.redo,
    {
      EditorAction.none,
      EditorAction.undo,
      EditorAction.redo,
      EditorAction.toggleEraser,
    },
  ),
  EditorGesture.fingerLongPress: (
    EditorAction.contextMenu,
    {EditorAction.none, EditorAction.contextMenu},
  ),
  EditorGesture.penButton: (
    EditorAction.eraserWhileHeld,
    {
      EditorAction.none,
      EditorAction.eraserWhileHeld,
      EditorAction.lassoWhileHeld,
    },
  ),
  EditorGesture.invertedStylus: (
    EditorAction.eraserWhileHeld,
    {EditorAction.none, EditorAction.eraserWhileHeld},
  ),
  EditorGesture.pencilDoubleTap: (
    EditorAction.followSystem,
    {
      EditorAction.none,
      EditorAction.followSystem,
      EditorAction.toggleEraser,
      EditorAction.previousTool,
      EditorAction.colorPalette,
      EditorAction.toolPalette,
      EditorAction.undo,
    },
  ),
  EditorGesture.pencilSqueeze: (
    EditorAction.followSystem,
    {
      EditorAction.none,
      EditorAction.followSystem,
      EditorAction.toolPalette,
      EditorAction.colorPalette,
      EditorAction.toggleEraser,
    },
  ),
};

/// The three gestures that have a v1.4 bool.
const _withBool = {
  EditorGesture.twoFingerTap,
  EditorGesture.threeFingerTap,
  EditorGesture.fingerLongPress,
};

bool? _boolOf(GestureSettings g, EditorGesture gesture) => switch (gesture) {
  EditorGesture.twoFingerTap => g.twoFingerTapUndo,
  EditorGesture.threeFingerTap => g.threeFingerTapRedo,
  EditorGesture.fingerLongPress => g.longPressMenu,
  _ => null,
};

/// Round trip through a JSON string, as CORE stores it.
Map<String, Object?> _viaJsonString(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  group('the contract table (7 rows)', () {
    test('covers every gesture', () {
      expect(_table.keys.toSet(), EditorGesture.values.toSet());
    });

    for (final MapEntry(key: gesture, value: (byDefault, allowed))
        in _table.entries) {
      test('${gesture.name}: default ${byDefault.name}, '
          '${allowed.length} allowed actions', () {
        expect(GestureSettings.defaultFor(gesture), byDefault);
        expect(GestureSettings.allowedFor(gesture), allowed);
        expect(
          GestureSettings.allowedFor(gesture),
          contains(GestureSettings.defaultFor(gesture)),
        );
        expect(
          GestureSettings.allowedFor(gesture),
          contains(EditorAction.none),
          reason: 'every gesture can be turned off',
        );
        expect(GestureSettings.defaults.actionFor(gesture), byDefault);
      });
    }

    test('defaults: bools true, actions empty', () {
      const defaults = GestureSettings.defaults;
      expect(defaults.twoFingerTapUndo, isTrue);
      expect(defaults.threeFingerTapRedo, isTrue);
      expect(defaults.longPressMenu, isTrue);
      expect(defaults.actions, isEmpty);
      expect(
        defaults,
        GestureSettings(actions: <EditorGesture, EditorAction>{}),
      );
    });
  });

  group('actionFor', () {
    test('① an allowed actions entry wins over the v1.4 bool', () {
      const settings = GestureSettings(
        twoFingerTapUndo: false,
        actions: {EditorGesture.twoFingerTap: EditorAction.redo},
      );
      expect(settings.actionFor(EditorGesture.twoFingerTap), EditorAction.redo);
    });

    test('② a false v1.4 bool without an entry → none', () {
      const settings = GestureSettings(
        twoFingerTapUndo: false,
        threeFingerTapRedo: false,
        longPressMenu: false,
      );
      for (final gesture in _withBool) {
        expect(
          settings.actionFor(gesture),
          EditorAction.none,
          reason: '$gesture',
        );
      }
    });

    test('③ otherwise the default', () {
      const settings = GestureSettings(
        actions: {EditorGesture.penButton: EditorAction.lassoWhileHeld},
      );
      for (final gesture in EditorGesture.values) {
        expect(
          settings.actionFor(gesture),
          gesture == EditorGesture.penButton
              ? EditorAction.lassoWhileHeld
              : GestureSettings.defaultFor(gesture),
        );
      }
    });

    test('an entry outside allowedFor is not used', () {
      const settings = GestureSettings(
        longPressMenu: false,
        actions: {
          EditorGesture.fingerLongPress: EditorAction.undo,
          EditorGesture.invertedStylus: EditorAction.lassoWhileHeld,
        },
      );
      expect(
        settings.actionFor(EditorGesture.fingerLongPress),
        EditorAction.none,
        reason: 'falls through to the false bool',
      );
      expect(
        settings.actionFor(EditorGesture.invertedStylus),
        EditorAction.eraserWhileHeld,
      );
    });
  });

  group('fromJson', () {
    test(r'v1.4 JSON {"twoFingerUndo":false,…} → actionFor(twoFingerTap) '
        '== none', () {
      final settings = GestureSettings.fromJson({
        'twoFingerUndo': false,
        'threeFingerRedo': true,
        'longPressMenu': true,
      });
      expect(settings.actionFor(EditorGesture.twoFingerTap), EditorAction.none);
      expect(
        settings.actionFor(EditorGesture.threeFingerTap),
        EditorAction.redo,
      );
      expect(
        settings.actionFor(EditorGesture.fingerLongPress),
        EditorAction.contextMenu,
      );
      expect(settings.actions, isEmpty);
      expect(
        settings,
        const GestureSettings(twoFingerTapUndo: false),
        reason: 'the v1.4 value as the 1st round read it',
      );
    });

    test('v1.4 JSON with every bool false / all true / missing', () {
      final off = GestureSettings.fromJson({
        'twoFingerUndo': false,
        'threeFingerRedo': false,
        'longPressMenu': false,
      });
      for (final gesture in EditorGesture.values) {
        expect(
          off.actionFor(gesture),
          _withBool.contains(gesture)
              ? EditorAction.none
              : GestureSettings.defaultFor(gesture),
        );
      }
      expect(GestureSettings.fromJson(const {}), GestureSettings.defaults);
      expect(
        GestureSettings.fromJson({
          'twoFingerUndo': true,
          'threeFingerRedo': true,
          'longPressMenu': true,
        }),
        GestureSettings.defaults,
      );
    });

    test('a mistyped v1.4 bool takes its default (true)', () {
      final settings = GestureSettings.fromJson({
        'twoFingerUndo': 0,
        'threeFingerRedo': 'false',
        'longPressMenu': null,
      });
      expect(settings, GestureSettings.defaults);
    });

    test('"actions" entries are read by EditorGesture / EditorAction name', () {
      final settings = GestureSettings.fromJson({
        'twoFingerUndo': true,
        'threeFingerRedo': false,
        'longPressMenu': true,
        'actions': {
          'penButton': 'lassoWhileHeld',
          'threeFingerTap': 'none',
          'twoFingerTap': 'redo',
        },
      });
      expect(settings.actions, {
        EditorGesture.penButton: EditorAction.lassoWhileHeld,
        EditorGesture.threeFingerTap: EditorAction.none,
        EditorGesture.twoFingerTap: EditorAction.redo,
      });
      expect(settings.actionFor(EditorGesture.twoFingerTap), EditorAction.redo);
      expect(
        settings.actionFor(EditorGesture.threeFingerTap),
        EditorAction.none,
      );
      expect(
        settings.actionFor(EditorGesture.penButton),
        EditorAction.lassoWhileHeld,
      );
    });

    test('unknown gestures, unknown actions and actions outside allowedFor '
        'are dropped', () {
      final settings = GestureSettings.fromJson({
        'actions': {
          'fourFingerTap': 'undo', // unknown gesture
          'twoFingerTap': 'teleport', // unknown action
          'threeFingerTap': 'contextMenu', // not allowed for this gesture
          'invertedStylus': 'lassoWhileHeld', // not allowed
          'penButton': 7, // not a name
          'fingerLongPress': 'none', // kept
          'pencilSqueeze': 'toolPalette', // kept
        },
      });
      expect(settings.actions, {
        EditorGesture.fingerLongPress: EditorAction.none,
        EditorGesture.pencilSqueeze: EditorAction.toolPalette,
      });
      expect(settings.actionFor(EditorGesture.twoFingerTap), EditorAction.undo);
      expect(
        settings.actionFor(EditorGesture.threeFingerTap),
        EditorAction.redo,
      );
      expect(
        settings.actionFor(EditorGesture.invertedStylus),
        EditorAction.eraserWhileHeld,
      );
    });

    test('"actions" that is not an object is ignored as a whole', () {
      for (final value in <Object?>[
        ['twoFingerTap'],
        'twoFingerTap=redo',
        3,
        null,
      ]) {
        final settings = GestureSettings.fromJson({
          'twoFingerUndo': false,
          'actions': value,
        });
        expect(settings.actions, isEmpty, reason: '$value');
        expect(
          settings.actionFor(EditorGesture.twoFingerTap),
          EditorAction.none,
          reason: 'the v1.4 bool still applies',
        );
      }
    });

    test('an "actions" map with non-string keys keeps its string keys', () {
      final settings = GestureSettings.fromJson({
        'actions': <Object?, Object?>{1: 'undo', 'twoFingerTap': 'redo'},
      });
      expect(settings.actions, {EditorGesture.twoFingerTap: EditorAction.redo});
    });

    test('a false bool next to an actions entry for the same gesture reads '
        'the entry; the bool then follows it', () {
      // An old app turned the gesture off after this app had set 'redo'
      // (04-editor 4.3.2 '옛 앱과 섞일 때'): the entry wins.
      final settings = GestureSettings.fromJson({
        'twoFingerUndo': false,
        'actions': {'twoFingerTap': 'redo'},
      });
      expect(settings.actionFor(EditorGesture.twoFingerTap), EditorAction.redo);
      expect(settings.twoFingerTapUndo, isTrue);
    });

    test('the result is consistent: each v1.4 bool == (action != none)', () {
      final inputs = <Map<String, Object?>>[
        {'twoFingerUndo': false},
        {
          'longPressMenu': true,
          'actions': {'fingerLongPress': 'none'},
        },
        {
          'threeFingerRedo': false,
          'actions': {'threeFingerTap': 'toggleEraser'},
        },
      ];
      for (final json in inputs) {
        final settings = GestureSettings.fromJson(json);
        for (final gesture in _withBool) {
          expect(
            _boolOf(settings, gesture),
            settings.actionFor(gesture) != EditorAction.none,
            reason: '$json $gesture',
          );
        }
      }
    });
  });

  group('toJson', () {
    test('defaults: the three v1.4 keys and an empty "actions"', () {
      expect(GestureSettings.defaults.toJson(), {
        'twoFingerUndo': true,
        'threeFingerRedo': true,
        'longPressMenu': true,
        'actions': <String, Object?>{},
      });
    });

    test('bool = actionFor(gesture) != none', () {
      const settings = GestureSettings(
        actions: {
          EditorGesture.twoFingerTap: EditorAction.none,
          EditorGesture.threeFingerTap: EditorAction.toggleEraser,
          EditorGesture.fingerLongPress: EditorAction.none,
        },
      );
      final json = settings.toJson();
      expect(json['twoFingerUndo'], isFalse);
      expect(json['threeFingerRedo'], isTrue);
      expect(json['longPressMenu'], isFalse);

      final fromBool = const GestureSettings(longPressMenu: false).toJson();
      expect(fromBool['longPressMenu'], isFalse);
      expect(fromBool['actions'], isEmpty);
    });

    test('"actions" holds the explicit entries only, by gesture name', () {
      const settings = GestureSettings(
        threeFingerTapRedo: false,
        actions: {
          EditorGesture.twoFingerTap: EditorAction.redo,
          EditorGesture.threeFingerTap: EditorAction.none,
          EditorGesture.penButton: EditorAction.lassoWhileHeld,
        },
      );
      final json = settings.toJson();
      final actions = json['actions']! as Map<String, Object?>;
      expect(actions, {
        'penButton': 'lassoWhileHeld',
        'threeFingerTap': 'none',
        'twoFingerTap': 'redo',
      });
      expect(actions.keys.toList(), [
        'penButton',
        'threeFingerTap',
        'twoFingerTap',
      ]);
      // The 04-editor 4.3.2 example, key for key.
      expect(
        jsonEncode(json),
        jsonEncode({
          'twoFingerUndo': true,
          'threeFingerRedo': false,
          'longPressMenu': true,
          'actions': {
            'penButton': 'lassoWhileHeld',
            'threeFingerTap': 'none',
            'twoFingerTap': 'redo',
          },
        }),
      );
    });

    test('entries outside allowedFor are not written', () {
      const settings = GestureSettings(
        actions: {
          EditorGesture.fingerLongPress: EditorAction.redo,
          EditorGesture.pencilDoubleTap: EditorAction.undo,
        },
      );
      expect(settings.toJson()['actions'], {'pencilDoubleTap': 'undo'});
    });
  });

  group('round trip', () {
    test('every allowed action of every gesture survives JSON text', () {
      for (final gesture in EditorGesture.values) {
        for (final action in GestureSettings.allowedFor(gesture)) {
          final settings = GestureSettings.defaults.withAction(gesture, action);
          final back = GestureSettings.fromJson(
            _viaJsonString(settings.toJson()),
          );
          expect(back, settings, reason: '$gesture $action');
          expect(back.actionFor(gesture), action);
        }
      }
    });

    test('several gestures at once', () {
      final settings = GestureSettings.defaults
          .withAction(EditorGesture.twoFingerTap, EditorAction.redo)
          .withAction(EditorGesture.threeFingerTap, EditorAction.none)
          .withAction(EditorGesture.penButton, EditorAction.lassoWhileHeld)
          .withAction(EditorGesture.pencilDoubleTap, EditorAction.undo)
          .withAction(EditorGesture.pencilSqueeze, EditorAction.colorPalette);
      final back = GestureSettings.fromJson(_viaJsonString(settings.toJson()));
      expect(back, settings);
      expect(back.hashCode, settings.hashCode);
      expect(
        back.actionFor(EditorGesture.fingerLongPress),
        EditorAction.contextMenu,
      );
    });

    test('v1.4 values (bools only) survive', () {
      const settings = GestureSettings(
        twoFingerTapUndo: false,
        longPressMenu: false,
      );
      expect(GestureSettings.fromJson(settings.toJson()), settings);
    });
  });

  group('withAction', () {
    test('sets the entry; the v1.4 bool follows action != none', () {
      final off = GestureSettings.defaults.withAction(
        EditorGesture.twoFingerTap,
        EditorAction.none,
      );
      expect(off.actions, {EditorGesture.twoFingerTap: EditorAction.none});
      expect(off.twoFingerTapUndo, isFalse);
      expect(off.actionFor(EditorGesture.twoFingerTap), EditorAction.none);

      final redo = off.withAction(
        EditorGesture.twoFingerTap,
        EditorAction.redo,
      );
      expect(redo.actions, {EditorGesture.twoFingerTap: EditorAction.redo});
      expect(redo.twoFingerTapUndo, isTrue);

      final pen = GestureSettings.defaults.withAction(
        EditorGesture.penButton,
        EditorAction.none,
      );
      expect(pen.actions, {EditorGesture.penButton: EditorAction.none});
      expect(
        [pen.twoFingerTapUndo, pen.threeFingerTapRedo, pen.longPressMenu],
        [true, true, true],
        reason: 'gestures without a bool leave the bools alone',
      );
    });

    test('the default removes the explicit entry', () {
      final changed = GestureSettings.defaults
          .withAction(EditorGesture.twoFingerTap, EditorAction.redo)
          .withAction(EditorGesture.penButton, EditorAction.lassoWhileHeld);
      final back = changed
          .withAction(EditorGesture.twoFingerTap, EditorAction.undo)
          .withAction(EditorGesture.penButton, EditorAction.eraserWhileHeld);
      expect(back.actions, isEmpty);
      expect(back, GestureSettings.defaults);
      expect(back.toJson()['actions'], isEmpty);
    });

    test('except for a gesture whose v1.4 bool is false: the default stays '
        'explicit', () {
      for (final gesture in _withBool) {
        final off = switch (gesture) {
          EditorGesture.twoFingerTap => const GestureSettings(
            twoFingerTapUndo: false,
          ),
          EditorGesture.threeFingerTap => const GestureSettings(
            threeFingerTapRedo: false,
          ),
          _ => const GestureSettings(longPressMenu: false),
        };
        expect(off.actionFor(gesture), EditorAction.none);
        final on = off.withAction(gesture, GestureSettings.defaultFor(gesture));
        expect(on.actions, {gesture: GestureSettings.defaultFor(gesture)});
        expect(on.actionFor(gesture), GestureSettings.defaultFor(gesture));
        expect(_boolOf(on, gesture), isTrue);
      }
    });

    test('an action outside allowedFor changes nothing', () {
      final settings = GestureSettings.defaults.withAction(
        EditorGesture.twoFingerTap,
        EditorAction.redo,
      );
      expect(
        identical(
          settings.withAction(EditorGesture.invertedStylus, EditorAction.undo),
          settings,
        ),
        isTrue,
      );
      expect(
        settings.withAction(EditorGesture.fingerLongPress, EditorAction.redo),
        settings,
      );
    });

    test('actionFor(gesture) == action for every allowed pair', () {
      const starts = [
        GestureSettings.defaults,
        GestureSettings(
          twoFingerTapUndo: false,
          threeFingerTapRedo: false,
          longPressMenu: false,
        ),
      ];
      for (final start in starts) {
        for (final gesture in EditorGesture.values) {
          for (final action in GestureSettings.allowedFor(gesture)) {
            final next = start.withAction(gesture, action);
            expect(next.actionFor(gesture), action, reason: '$gesture $action');
            for (final other in EditorGesture.values) {
              if (other == gesture) continue;
              expect(
                next.actionFor(other),
                start.actionFor(other),
                reason: 'other gestures keep their action',
              );
            }
          }
        }
      }
    });

    test('the returned actions map cannot be changed', () {
      final settings = GestureSettings.defaults.withAction(
        EditorGesture.twoFingerTap,
        EditorAction.redo,
      );
      expect(
        () => settings.actions[EditorGesture.penButton] = EditorAction.none,
        throwsUnsupportedError,
      );
    });
  });

  group('copyWith · == · hashCode', () {
    test('copyWith keeps the actions, replaces them and drops disallowed '
        'entries', () {
      final settings = GestureSettings.defaults.withAction(
        EditorGesture.penButton,
        EditorAction.lassoWhileHeld,
      );
      expect(settings.copyWith(), settings);
      expect(settings.copyWith(longPressMenu: false).actions, settings.actions);
      expect(
        settings
            .copyWith(
              actions: {
                EditorGesture.twoFingerTap: EditorAction.toggleEraser,
                EditorGesture.invertedStylus: EditorAction.undo, // not allowed
              },
            )
            .actions,
        {EditorGesture.twoFingerTap: EditorAction.toggleEraser},
      );
    });

    test('copyWith keeps its own copy of the actions map', () {
      final mine = {EditorGesture.twoFingerTap: EditorAction.redo};
      final settings = GestureSettings.defaults.copyWith(actions: mine);
      mine[EditorGesture.twoFingerTap] = EditorAction.none;
      expect(settings.actionFor(EditorGesture.twoFingerTap), EditorAction.redo);
      expect(
        () => settings.actions[EditorGesture.penButton] = EditorAction.none,
        throwsUnsupportedError,
      );
    });

    test('== compares the three bools and the actions map', () {
      const a = GestureSettings(
        actions: {EditorGesture.penButton: EditorAction.none},
      );
      final b = GestureSettings(
        actions: {EditorGesture.penButton: EditorAction.none},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(GestureSettings.defaults));
      expect(
        a,
        isNot(
          const GestureSettings(
            actions: {EditorGesture.penButton: EditorAction.eraserWhileHeld},
          ),
        ),
      );
      expect(
        a,
        isNot(
          const GestureSettings(
            twoFingerTapUndo: false,
            actions: {EditorGesture.penButton: EditorAction.none},
          ),
        ),
      );
      expect(GestureSettings.defaults.toString(), contains('actions: {}'));
    });
  });
}
