// API surface of pencil_bridge (contract 00-overview 7.2.13, docs/plans/m5-7/
// 01-infra.md 4.4.1, 4.4.2 and 6.12.4).
//
// 1. Export list: lib/pencil_bridge.dart is the only entry point; it exports
//    with `show` only, and the shown names are exactly the contract's seven
//    (PencilWire and the debug hooks' implementation stay internal).
// 2. Compile-time shape: every contract member is referenced with the
//    contract types, so a renamed / retyped / removed member breaks the build.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pencil_bridge/pencil_bridge.dart';

/// Contract 7.2.13: the names, nothing else.
const Set<String> contractNames = {
  'PencilBridge',
  'PencilEvent',
  'PencilTap',
  'PencilSqueeze',
  'PencilHover',
  'PencilRoll',
  'PencilCapabilities',
};

/// Every `export` directive of [source]: (uri, shown names or null without `show`).
List<(String, Set<String>?)> _exports(String source) {
  final out = <(String, Set<String>?)>[];
  final directive = RegExp(r'''^export\s+'([^']+)'([^;]*);''', multiLine: true);
  for (final m in directive.allMatches(source)) {
    final show = RegExp(r'\bshow\b([\s\S]*)').firstMatch(m.group(2)!);
    out.add((
      m.group(1)!,
      show == null
          ? null
          : {
              for (final n in show.group(1)!.split(','))
                if (n.trim().isNotEmpty) n.trim(),
            },
    ));
  }
  return out;
}

void main() {
  test('lib/ has one entry point', () {
    final entries = Directory('lib')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.dart'))
        .toSet();
    expect(entries, {'pencil_bridge.dart'});
  });

  test('the entry point shows exactly the contract names', () {
    final source = File('lib/pencil_bridge.dart').readAsStringSync();
    expect(source, isNot(contains("import 'dart:io'")));
    final exports = _exports(source);
    expect(exports, isNotEmpty);
    final shown = <String>{};
    for (final (uri, names) in exports) {
      expect(names, isNotNull, reason: "export '$uri' needs a show list");
      expect(uri, startsWith('src/'));
      shown.addAll(names!);
    }
    expect(shown, contractNames);
  });

  test('no file of lib/ imports dart:io (web-safe — contract 7.2.13)', () {
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      expect(
        file.readAsStringSync(),
        isNot(matches(RegExp(r'''import\s+['"]dart:io['"]'''))),
        reason: file.path,
      );
    }
  });

  test('contract shape (typed references)', () {
    // PencilBridge: static members with the contract types.
    const bool Function() isSupported = _isSupported;
    const Future<PencilCapabilities> Function() capabilities =
        PencilBridge.capabilities;
    const Stream<PencilEvent> Function() events = _events;
    expect(isSupported, isNotNull);
    expect(capabilities, isNotNull);
    expect(events, isNotNull);

    // PencilEvent is sealed with the four subtypes; each has timestamp.
    const List<PencilEvent> all = [
      PencilTap(
        Duration(seconds: 1),
        preferredAction: 'ignore',
        position: Offset(1, 2),
        z: 0.5,
      ),
      PencilSqueeze(
        Duration(seconds: 2),
        phase: 'began',
        preferredAction: 'ignore',
        position: Offset(1, 2),
        z: 0.5,
        roll: 0.1,
      ),
      PencilHover(
        Duration(seconds: 3),
        position: Offset(1, 2),
        z: 0.5,
        altitude: 1,
        azimuth: 2,
        roll: 3,
      ),
      PencilRoll(Duration(seconds: 4), angle: 1),
    ];
    final described = [
      for (final event in all)
        switch (event) {
          PencilTap(
            :final Duration timestamp,
            :final String preferredAction,
            :final Offset? position,
            :final double? z,
          ) =>
            'tap $timestamp $preferredAction $position $z',
          PencilSqueeze(
            :final String phase,
            :final String preferredAction,
            :final Offset? position,
            :final double? z,
            :final double? roll,
          ) =>
            'squeeze $phase $preferredAction $position $z $roll',
          PencilHover(
            :final Offset position,
            :final double? z,
            :final double? altitude,
            :final double? azimuth,
            :final double? roll,
          ) =>
            'hover $position $z $altitude $azimuth $roll',
          PencilRoll(:final double angle) => 'roll $angle',
        },
    ];
    expect(described, hasLength(4));

    const caps = PencilCapabilities(os: '17.5');
    final String os = caps.os;
    final List<bool> flags = [
      caps.squeeze,
      caps.hover,
      caps.roll,
      caps.prefersPencilOnlyDrawing,
    ];
    final List<String> actions = [
      caps.preferredTapAction,
      caps.preferredSqueezeAction,
    ];
    const PencilCapabilities unsupported = PencilCapabilities.unsupported;
    final PencilCapabilities Function(Map<Object?, Object?>) fromWire =
        PencilCapabilities.fromWire;
    expect(os, '17.5');
    expect(flags, everyElement(isFalse));
    expect(actions, everyElement('unknown'));
    expect(unsupported.os, '');
    expect(fromWire(const {'os': '1'}).os, '1');
  });
}

bool _isSupported() => PencilBridge.isSupported;
Stream<PencilEvent> _events() => PencilBridge.events;
