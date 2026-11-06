// The channel names, wire strings and event decoding of pencil_bridge
// (docs/plans/m5-7/01-infra.md 4.4.2 and 4.4.3). The Swift source must repeat
// these constants (ios/pencil_bridge/Sources/pencil_bridge/PencilWire.swift) —
// test/pencil_wire_contract_test.dart compares them (J12).
import 'dart:ui' show Offset;

import 'pencil_events.dart';

abstract final class PencilWire {
  static const String eventChannel = 'dev.noteapp/pencil/events';
  static const String methodChannel = 'dev.noteapp/pencil/methods';
  static const String capabilitiesMethod = 'capabilities';
  static const Set<String> types = {'tap', 'squeeze', 'hover', 'roll'};
  static const Set<String> actions = {
    'ignore',
    'switchEraser',
    'switchPrevious',
    'showColorPalette',
    'showInkAttributes',
    'showContextualPalette',
    'runSystemShortcut',
    'unknown',
  };
  static const Set<String> phases = {'began', 'changed', 'ended', 'cancelled'};

  /// Event keys per `type` (4.4.3): required / optional, `type` and `t`
  /// excluded (every event has both).
  static const Map<String, ({Set<String> required, Set<String> optional})>
  eventKeys = {
    'tap': (required: {'action'}, optional: {'x', 'y', 'z'}),
    'squeeze': (
      required: {'phase', 'action'},
      optional: {'x', 'y', 'z', 'roll'},
    ),
    'hover': (
      required: {'x', 'y'},
      optional: {'z', 'altitude', 'azimuth', 'roll'},
    ),
    'roll': (required: {'angle'}, optional: <String>{}),
  };

  /// null = drop (unknown type, missing required key, wrong value type).
  ///
  /// Numbers are taken as `num` (`toDouble()`), so an int is accepted; a
  /// non-finite `t` is a wrong value. A key whose value is null counts as
  /// missing. Unknown `action` / `phase` strings are kept as they are (the
  /// app adapter maps them). A position (`x`, `y`) of tap / squeeze needs
  /// both values; with only one of them the event has no position.
  static PencilEvent? decode(Object? event) {
    if (event is! Map) return null;
    final type = event['type'];
    if (type is! String || !types.contains(type)) return null;
    final t = event['t'];
    if (t is! num || !t.isFinite) return null;
    final timestamp = Duration(microseconds: (t * 1e6).round());

    // Every key of the table must hold the right type when present.
    final keys = eventKeys[type]!;
    for (final key in keys.required) {
      if (event[key] == null) return null;
    }
    for (final key in {...keys.required, ...keys.optional}) {
      final value = event[key];
      if (value == null) continue;
      final wantsString = key == 'action' || key == 'phase';
      if (wantsString ? value is! String : value is! num) return null;
    }
    double? number(String key) => (event[key] as num?)?.toDouble();
    String string(String key) => event[key]! as String;
    Offset? position() {
      final x = number('x');
      final y = number('y');
      return x == null || y == null ? null : Offset(x, y);
    }

    return switch (type) {
      'tap' => PencilTap(
        timestamp,
        preferredAction: string('action'),
        position: position(),
        z: number('z'),
      ),
      'squeeze' => PencilSqueeze(
        timestamp,
        phase: string('phase'),
        preferredAction: string('action'),
        position: position(),
        z: number('z'),
        roll: number('roll'),
      ),
      'hover' => PencilHover(
        timestamp,
        position: position()!,
        z: number('z'),
        altitude: number('altitude'),
        azimuth: number('azimuth'),
        roll: number('roll'),
      ),
      _ => PencilRoll(timestamp, angle: number('angle')!),
    };
  }
}
