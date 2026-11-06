// The Swift side of pencil_bridge cannot be compiled in the container (no
// Xcode — compiling is ios-compile.yml's, U19), so this test compares the
// Swift sources with the Dart side as text (docs/plans/m5-7/01-infra.md 4.4.3,
// 6.12.2 and 6.12.4).
//
// ⓪ plugin class = pluginClass, adopts FlutterPlugin, register(with:) (R2-B1)
// ① channel names ② `type` values ③ event keys per type (4.4.3 table) and the
// capabilities keys ④ action / phase names ⑤ iPadOS 16 / 17.5 APIs only
// inside @available / #available ⑥ pubspec pluginClass ⑦ iOS 15.0 ≤ the
// app's deployment target ⑧ the podspec builds every Swift file ⑨ attach on
// registrar.viewController first, simultaneous recognition, passive roll
// recognizer, ≤ 60 Hz (J12).
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pencil_bridge/pencil_bridge.dart';
import 'package:pencil_bridge/src/wire.dart';

const _sourcesDir = 'ios/pencil_bridge/Sources/pencil_bridge';
const _pluginSwift = '$_sourcesDir/PencilBridgePlugin.swift';
const _wireSwift = '$_sourcesDir/PencilWire.swift';
const _streamSwift = '$_sourcesDir/PencilEventStream.swift';
const _rollSwift = '$_sourcesDir/PencilRollRecognizer.swift';
const _packageSwift = 'ios/pencil_bridge/Package.swift';
const _podspec = 'ios/pencil_bridge.podspec';

/// Swift source without `//` line comments and `/* */` block comments, so a
/// declaration that only appears in a comment does not count. (The sources
/// have no `//` inside a string literal.)
String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// [code] with every string literal emptied (`"…"` → `""`): braces and names
/// inside strings no longer count.
String _withoutStrings(String code) =>
    code.replaceAll(RegExp(r'"(?:[^"\\\n]|\\.)*"'), '""');

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return file.readAsStringSync();
}

String _code(String path) => _withoutComments(_read(path));

/// Every Swift file of the target, comments removed.
Map<String, String> _allSwift() => {
  for (final file
      in Directory(_sourcesDir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.swift')))
    file.path: _withoutComments(file.readAsStringSync()),
};

/// Index of the `}` that closes the `{` at [open] ([code] without strings).
int _closing(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    if (code[i] == '{') depth++;
    if (code[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  fail('unbalanced braces after $open');
}

/// The body (between the braces) of the first declaration matching
/// [header]. Braces are matched on the string-free text, the body is cut
/// from [code] (strings kept; emptying keeps the offsets).
String _body(String code, Pattern header) {
  final match = header.allMatches(code).firstOrNull;
  expect(match, isNotNull, reason: 'no `$header` in the Swift source');
  final bare = _blankStrings(code);
  final open = bare.indexOf('{', match!.end);
  return code.substring(open + 1, _closing(bare, open));
}

/// Like [_withoutStrings] but keeps every offset (contents → spaces).
String _blankStrings(String code) => code.replaceAllMapped(
  RegExp(r'"(?:[^"\\\n]|\\.)*"'),
  (m) => '"${' ' * (m.group(0)!.length - 2)}"',
);

Set<String> _all(Pattern pattern, String text, [int group = 1]) => {
  for (final m in pattern.allMatches(text)) m.group(group)!,
};

/// Dictionary-literal keys (`"k": …`) of a Swift body.
Set<String> _literalKeys(String body) =>
    _all(RegExp(r'"(\w+)"\s*:(?!:)'), body);

/// Keys set later (`event["k"] = …`).
Set<String> _subscriptKeys(String body) =>
    _all(RegExp(r'event\["(\w+)"\]\s*='), body);

// ---------------------------------------------------------------------------
// Availability (⑤)

/// iOS version as major * 100 + minor (17.5 → 1705). 0 = no guarantee.
int _version(String major, String? minor) =>
    int.parse(major) * 100 + int.parse(minor ?? '0');

final _availability = RegExp(r'([@#])available\(\s*iOS\s+(\d+)(?:\.(\d+))?');

/// The highest iOS version a brace header (`… {`) guarantees for its block:
/// `@available(iOS x, *)` on a declaration or `if #available(iOS x, *)`.
/// `guard #available … else {` and `else {` blocks guarantee nothing.
int _headerVersion(String header, {bool attributesOnly = false}) {
  final trimmed = header.trim();
  if (RegExp(r'\bguard\b').hasMatch(trimmed) ||
      RegExp(r'^else\b(?!\s+if\b)').hasMatch(trimmed)) {
    return 0;
  }
  var best = 0;
  for (final m in _availability.allMatches(header)) {
    if (attributesOnly && m.group(1) != '@') continue;
    best = math.max(best, _version(m.group(2)!, m.group(3)));
  }
  return best;
}

/// The iOS version guaranteed at [offset] of [code] (comments and strings
/// removed): the highest one of the blocks around it, or of the declaration
/// whose header [offset] is in (`@available(iOS 17.5, *) func f(… x …) {`).
int _guaranteedAt(String code, int offset) {
  final stack = <int>[];
  var boundary = -1;
  for (var i = 0; i < offset; i++) {
    final c = code[i];
    if (c == '{') {
      final outer = stack.isEmpty ? 0 : stack.last;
      stack.add(
        math.max(outer, _headerVersion(code.substring(boundary + 1, i))),
      );
      boundary = i;
    } else if (c == '}') {
      stack.removeLast();
      boundary = i;
    } else if (c == ';') {
      boundary = i;
    }
  }
  var best = stack.isEmpty ? 0 : stack.last;
  // In a declaration header: the text up to the next `{`, with no `}` or `;`
  // in between, holds `func` / `class` / `init` … and an @available.
  final next = code.indexOf('{', offset);
  if (next >= 0) {
    final header = code.substring(boundary + 1, next);
    if (!header.contains('}') &&
        !header.contains(';') &&
        RegExp(r'\b(func|class|struct|enum|extension|init)\b')
            .hasMatch(header)) {
      best = math.max(best, _headerVersion(header, attributesOnly: true));
    }
  }
  // In the condition of `if #available(iOS x, *), … x …` itself.
  final condition = code.substring(boundary + 1, offset);
  if (RegExp(r'^\s*(else\s+)?(if|while)\b').hasMatch(condition)) {
    best = math.max(best, _headerVersion(condition));
  }
  return best;
}

/// APIs newer than the plugin's iOS 15.0 that the sources use (6.12.2 table).
const Map<String, int> _newerApis = {
  'didReceiveTap': 1705,
  'didReceiveSqueeze': 1705,
  'hoverPose': 1705,
  'rollAngle': 1705,
  'preferredSqueezeAction': 1705,
  'showContextualPalette': 1705,
  'runSystemShortcut': 1705,
  'PencilRollRecognizer': 1705,
  'altitudeAngle': 1604,
  'azimuthAngle': 1604,
  'zOffset': 1601,
  'showInkAttributes': 1600,
};

// ---------------------------------------------------------------------------
// pubspec (⓪ ⑥)

/// `flutter: plugin: platforms:` of pubspec.yaml, read as text (the package
/// has no YAML dependency): the platform names and the iOS `pluginClass`.
({Set<String> platforms, String? pluginClass}) _pluginSection() {
  final lines = _read('pubspec.yaml').split('\n');
  final platforms = <String>{};
  String? pluginClass;
  var inPlatforms = false;
  for (final line in lines) {
    if (line.trim() == 'platforms:') {
      inPlatforms = true;
      continue;
    }
    if (!inPlatforms || line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    if (indent <= 4) break; // left `platforms:`
    final platform = RegExp(r'^      (\w+):\s*$').firstMatch(line);
    if (platform != null) platforms.add(platform.group(1)!);
    final cls = RegExp(r'^\s+pluginClass:\s*(\w+)\s*$').firstMatch(line);
    if (cls != null) pluginClass = cls.group(1);
  }
  return (platforms: platforms, pluginClass: pluginClass);
}

String _pluginClass() {
  final section = _pluginSection();
  expect(section.platforms, {
    'ios',
  }, reason: 'pencil_bridge is implemented on iOS only (contract 7.2.13)');
  expect(section.pluginClass, isNotNull);
  return section.pluginClass!;
}

/// A Dart wire map with every key Swift sets: numbers 1.5, the string keys
/// a known name.
Map<String, Object?> _wireMap(String type, Set<String> keys) => {
  for (final key in keys)
    key: switch (key) {
      'type' => type,
      'action' => 'switchEraser',
      'phase' => 'began',
      _ => 1.5,
    },
};

RegExp _builder(String type) => RegExp('static\\s+func\\s+${type}Event\\s*\\(');

void main() {
  group('⓪ ⑥ plugin class', () {
    test('pluginClass is PencilBridgePlugin (iOS only)', () {
      expect(_pluginClass(), 'PencilBridgePlugin');
    });

    test('the Swift plugin class adopts FlutterPlugin and registers', () {
      final swift = _code(_pluginSwift);
      final className = _pluginClass();
      expect(swift, contains('import Flutter'));
      expect(
        RegExp(
          r'public\s+(final\s+)?class\s+' +
              RegExp.escape(className) +
              r'\s*:\s*NSObject\s*,\s*FlutterPlugin\b',
        ).hasMatch(swift),
        isTrue,
        reason:
            'expected `public final class $className: NSObject, FlutterPlugin`',
      );
      expect(
        RegExp(
          r'public\s+static\s+func\s+register\s*\(\s*with\s+registrar\s*:\s*'
          r'FlutterPluginRegistrar\s*\)',
        ).hasMatch(swift),
        isTrue,
        reason:
            'expected `public static func register(with registrar: '
            'FlutterPluginRegistrar)`',
      );
      // Exactly one plugin class in the Sources directory.
      final plugins = _allSwift().entries
          .where((e) => RegExp(r'\bFlutterPlugin\b').hasMatch(e.value))
          .map((e) => e.key)
          .toList();
      expect(plugins, [_pluginSwift]);
    });

    test('registration only creates the channels: no UI work (6.12.2)', () {
      final register = _body(
        _code(_pluginSwift),
        RegExp(r'static\s+func\s+register\s*\('),
      );
      for (final ui in [
        'UIApplication',
        'keyWindow',
        'addInteraction',
        'addGestureRecognizer',
        'viewController',
      ]) {
        expect(register, isNot(contains(ui)), reason: ui);
      }
      expect(register, contains('registrar.addMethodCallDelegate(instance'));
      expect(register, contains('.setStreamHandler(events)'));
    });
  });

  group('① channel names', () {
    test('the Swift constants equal PencilWire (Dart)', () {
      final wire = _code(_wireSwift);
      String constant(String name) {
        final m = RegExp('static\\s+let\\s+$name\\s*=\\s*"([^"]*)"')
            .firstMatch(wire);
        expect(m, isNotNull, reason: 'static let $name');
        return m!.group(1)!;
      }

      expect(constant('eventChannel'), PencilWire.eventChannel);
      expect(constant('methodChannel'), PencilWire.methodChannel);
      expect(constant('capabilitiesMethod'), PencilWire.capabilitiesMethod);
    });

    test('the channels and the method use those constants', () {
      final plugin = _code(_pluginSwift);
      expect(
        plugin,
        matches(
          RegExp(r'FlutterMethodChannel\(\s*name:\s*PencilWire\.methodChannel'),
        ),
      );
      expect(
        plugin,
        matches(
          RegExp(r'FlutterEventChannel\(\s*name:\s*PencilWire\.eventChannel'),
        ),
      );
      final handle = _body(plugin, RegExp(r'func\s+handle\s*\('));
      expect(handle, contains('case PencilWire.capabilitiesMethod:'));
      expect(handle, contains('result(FlutterMethodNotImplemented)'));
      // The strings themselves appear once (in PencilWire.swift).
      for (final name in [
        PencilWire.eventChannel,
        PencilWire.methodChannel,
        PencilWire.capabilitiesMethod,
      ]) {
        final count = _allSwift().values
            .map((code) => '"$name"'.allMatches(code).length)
            .fold(0, (a, b) => a + b);
        expect(count, 1, reason: name);
      }
    });
  });

  group('② ③ events (4.4.3)', () {
    late final wire = _code(_wireSwift);

    test('one builder per type; `type` values = PencilWire.types', () {
      final types = _all(RegExp(r'"type"\s*:\s*"(\w+)"'), wire);
      expect(types, PencilWire.types);
      for (final type in PencilWire.types) {
        expect(
          _all(RegExp(r'"type"\s*:\s*"(\w+)"'), _body(wire, _builder(type))),
          {type},
          reason: '${type}Event',
        );
      }
    });

    for (final MapEntry(key: type, value: keys)
        in PencilWire.eventKeys.entries) {
      test(
        '$type: literal keys = type, t + required; set later = optional',
        () {
          final body = _body(wire, _builder(type));
          expect(_literalKeys(body), {'type', 't', ...keys.required});
          expect(_subscriptKeys(body), keys.optional);
        },
      );

      test('$type: the maps Swift sends decode in Dart', () {
        final body = _body(wire, _builder(type));
        final required = _literalKeys(body);
        final all = {...required, ..._subscriptKeys(body)};
        for (final keys in [required, all]) {
          final decoded = PencilWire.decode(_wireMap(type, keys));
          expect(decoded, isNotNull, reason: '$type $keys');
          expect(decoded.runtimeType, switch (type) {
            'tap' => PencilTap,
            'squeeze' => PencilSqueeze,
            'hover' => PencilHover,
            _ => PencilRoll,
          });
        }
      });
    }

    test('every builder is used by the event stream', () {
      final stream = _code(_streamSwift);
      for (final type in PencilWire.types) {
        expect(stream, contains('PencilWire.${type}Event('), reason: type);
      }
    });

    test(
      'capabilities keys are the ones PencilCapabilities.fromWire reads',
      () {
        final body = _body(
          _code(_pluginSwift),
          RegExp(r'static\s+func\s+capabilities\s*\('),
        );
        const keys = {
          'os',
          'squeeze',
          'hover',
          'roll',
          'prefersPencilOnlyDrawing',
          'preferredTapAction',
          'preferredSqueezeAction',
        };
        expect(_literalKeys(body), keys);
        // Each key changes its field in Dart (none is read under another name).
        final decoded = PencilCapabilities.fromWire({
          'os': '17.5',
          'squeeze': true,
          'hover': true,
          'roll': true,
          'prefersPencilOnlyDrawing': true,
          'preferredTapAction': 'switchEraser',
          'preferredSqueezeAction': 'showContextualPalette',
        });
        expect(
          decoded,
          const PencilCapabilities(
            os: '17.5',
            squeeze: true,
            hover: true,
            roll: true,
            prefersPencilOnlyDrawing: true,
            preferredTapAction: 'switchEraser',
            preferredSqueezeAction: 'showContextualPalette',
          ),
        );
      },
    );
  });

  group('④ names', () {
    test('action names = PencilWire.actions; each case keeps its name', () {
      final body = _body(
        _code(_wireSwift),
        RegExp(r'static\s+func\s+actionName\s*\('),
      );
      expect(_all(RegExp(r'return\s+"(\w+)"'), body), PencilWire.actions);
      final cases = RegExp(r'case\s+\.(\w+)\s*:\s*return\s+"(\w+)"')
          .allMatches(body)
          .toList();
      expect(cases, isNotEmpty);
      for (final m in cases) {
        expect(m.group(2), m.group(1));
      }
      // The 17.5 switch names every action.
      expect({
        for (final m in cases) m.group(1)!,
      }, PencilWire.actions.difference({'unknown'}));
      expect(body, contains('@unknown default: return "unknown"'));
    });

    test(
      'squeeze phases = PencilWire.phases; an unknown phase is not sent',
      () {
        final body = _body(
          _code(_streamSwift),
          RegExp(r'didReceiveSqueeze\s+squeeze'),
        );
        final cases = RegExp(r'case\s+\.(\w+)\s*:\s*phase\s*=\s*"(\w+)"')
            .allMatches(body)
            .toList();
        expect({for (final m in cases) m.group(2)!}, PencilWire.phases);
        for (final m in cases) {
          expect(m.group(2), m.group(1));
        }
        expect(body, matches(RegExp(r'@unknown default:\s*return')));
      },
    );
  });

  group('⑤ availability', () {
    test('iPadOS 16 / 17.5 APIs are used only where they are available', () {
      final seen = <String>{};
      for (final MapEntry(key: path, value: code) in _allSwift().entries) {
        final bare = _withoutStrings(code);
        for (final MapEntry(key: api, value: needed) in _newerApis.entries) {
          for (final m in RegExp('\\b$api\\b').allMatches(bare)) {
            seen.add(api);
            final line = '\n'.allMatches(bare.substring(0, m.start)).length + 1;
            expect(
              _guaranteedAt(bare, m.start),
              greaterThanOrEqualTo(needed),
              reason:
                  '$path:$line uses $api outside an @available / '
                  '#available(iOS ${needed ~/ 100}.${needed % 100}, *)',
            );
          }
        }
      }
      // The check is not empty: the 17.5 APIs of the plan are there.
      expect(
        seen,
        containsAll([
          'didReceiveSqueeze',
          'rollAngle',
          'preferredSqueezeAction',
        ]),
      );
    });

    test('the availability reader itself (bad sources are caught)', () {
      int at(String code, String api) => _guaranteedAt(code, code.indexOf(api));
      expect(at('func f() { x.rollAngle }', 'rollAngle'), 0);
      expect(
        at('if #available(iOS 17.5, *) { x.rollAngle }', 'rollAngle'),
        1705,
      );
      expect(
        at(
          'if #available(iOS 17.5, *) { a } else { x.rollAngle }',
          'rollAngle',
        ),
        0,
      );
      expect(
        at('guard #available(iOS 17.5, *) else { x.rollAngle }', 'rollAngle'),
        0,
      );
      expect(
        at(
          '@available(iOS 17.5, *)\nfunc f(_ s: didReceiveSqueeze) { }',
          'didReceiveSqueeze',
        ),
        1705,
      );
      expect(
        at(
          'let a = x.preferredSqueezeAction\nif #available(iOS 17.5, *) { }',
          'preferredSqueezeAction',
        ),
        0,
      );
      expect(
        at(
          '@available(iOS 17.5, *) class C { func f() { if y { x.rollAngle } } }',
          'rollAngle',
        ),
        1705,
      );
      expect(at('if #available(iOS 16.1, *) { z.zOffset }', 'zOffset'), 1601);
      expect(
        at(
          'if #available(iOS 16.0, *), a == .showInkAttributes { }',
          'showInkAttributes',
        ),
        1600,
      );
      expect(at('if a == .showInkAttributes { }', 'showInkAttributes'), 0);
      expect(
        at(
          'if x { } else if #available(iOS 17.5, *) { x.rollAngle }',
          'rollAngle',
        ),
        1705,
      );
    });
  });

  group('⑦ ⑧ build files', () {
    test('Package.swift follows the Flutter plugin SwiftPM layout', () {
      final package = _code(_packageSwift);
      expect(_read(_packageSwift), startsWith('// swift-tools-version: 5.9'));
      expect(package, contains('name: "pencil_bridge"'));
      expect(package, contains('.iOS("15.0")'));
      expect(package, contains('targets: ["pencil_bridge"]'));
      expect(
        package,
        contains(
          '.package(name: "FlutterFramework", path: "../FlutterFramework")',
        ),
      );
      expect(
        package,
        contains(
          '.product(name: "FlutterFramework", package: "FlutterFramework")',
        ),
      );
      // SwiftPM finds the target's sources at Sources/<target name>/ — all of
      // them (no sources: / exclude:).
      expect(Directory(_sourcesDir).existsSync(), isTrue);
      expect(package, isNot(contains('sources:')));
      expect(package, isNot(contains('exclude:')));
      expect(package, isNot(contains('macOS')));
    });

    test('the podspec builds every Swift file of the target for iOS', () {
      final podspec = _read(_podspec);
      expect(podspec, contains("s.name             = 'pencil_bridge'"));
      final sources = RegExp(r"s\.source_files\s*=\s*'([^']+)'")
          .firstMatch(podspec);
      expect(sources, isNotNull);
      expect(
        sources!.group(1),
        'pencil_bridge/Sources/pencil_bridge/**/*.swift',
      );
      // The pattern is relative to ios/ (the podspec's directory) and every
      // Swift file but Package.swift lives under it.
      final swiftFiles = Directory('ios')
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.swift') && !p.endsWith('Package.swift'))
          .toSet();
      expect(swiftFiles, {_pluginSwift, _wireSwift, _streamSwift, _rollSwift});
      expect(podspec, contains("s.platform = :ios, '15.0'"));
      expect(podspec, contains("s.dependency 'Flutter'"));
    });

    test("iOS 15.0 is at most the app's deployment target", () {
      const plugin = 1500;
      final podfile = _read('../../app/ios/Podfile');
      final platform = RegExp(
        r"^platform :ios, '(\d+)\.(\d+)'",
        multiLine: true,
      ).firstMatch(podfile);
      expect(platform, isNotNull);
      expect(
        _version(platform!.group(1)!, platform.group(2)),
        greaterThanOrEqualTo(plugin),
      );
      final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = (\d+)\.(\d+);')
          .allMatches(_read('../../app/ios/Runner.xcodeproj/project.pbxproj'));
      expect(targets, isNotEmpty);
      for (final m in targets) {
        expect(_version(m.group(1)!, m.group(2)), greaterThanOrEqualTo(plugin));
      }
    });
  });

  group('⑨ attach, recognizers, rate (6.12.2)', () {
    late final stream = _code(_streamSwift);

    test('the stream handler attaches on listen and detaches on cancel', () {
      expect(
        stream,
        matches(
          RegExp(
            r'class\s+PencilEventStream\s*:\s*NSObject\s*,\s*'
            r'FlutterStreamHandler',
          ),
        ),
      );
      expect(
        _body(stream, RegExp(r'func\s+onListen\s*\(')),
        contains('attach()'),
      );
      final cancel = _body(stream, RegExp(r'func\s+onCancel\s*\('));
      expect(cancel, contains('detach()'));
      expect(cancel, contains('eventSink = nil'));
    });

    test('registrar.viewController first, then the key window, then wait', () {
      final target = _body(stream, RegExp(r'func\s+targetView\s*\('));
      final flutterView = target.indexOf('registrar?.viewController?.view');
      expect(flutterView, isNonNegative);
      expect(target.indexOf('keyWindow'), greaterThan(flutterView));
      final attach = _body(
        stream,
        RegExp(r'private\s+func\s+attach\s*\(\s*\)'),
      );
      expect(attach, contains('targetView()'));
      expect(attach, contains('UIWindow.didBecomeKeyNotification'));
    });

    test('interaction and recognizers: delegate self, pencil only, no '
        'cancelling; simultaneous recognition → true', () {
      final attach = _body(stream, RegExp(r'func\s+attach\s*\(\s*to\s+view'));
      expect(attach, contains('UIPencilInteraction()'));
      expect(attach, contains('view.addInteraction(interaction)'));
      expect(attach, contains('UIHoverGestureRecognizer('));
      expect(
        attach,
        contains(
          'hover.allowedTouchTypes = '
          '[NSNumber(value: UITouch.TouchType.pencil.rawValue)]',
        ),
      );
      expect(attach, contains('hover.cancelsTouchesInView = false'));
      expect(attach, contains('PencilRollRecognizer('));
      for (final name in ['interaction', 'hover', 'roll']) {
        expect(attach, contains('$name.delegate = self'), reason: name);
      }
      final simultaneous = _body(
        stream,
        RegExp(r'shouldRecognizeSimultaneouslyWith'),
      );
      expect(simultaneous.trim(), 'return true');
      // detach removes all three.
      final detach = _body(stream, RegExp(r'func\s+detach\s*\('));
      expect(detach, contains('removeInteraction(interaction)'));
      expect(detach, contains('removeGestureRecognizer(hover)'));
      expect(detach, contains('removeGestureRecognizer(roll)'));
      expect(detach, contains('stopObservingKeyWindow()'));
    });

    test('the roll recognizer is passive: never recognizes, never delays', () {
      final roll = _code(_rollSwift);
      expect(roll, contains('import UIKit.UIGestureRecognizerSubclass'));
      final init = _body(roll, RegExp(r'override\s+init\s*\('));
      const pencilOnly =
          'allowedTouchTypes = '
          '[NSNumber(value: UITouch.TouchType.pencil.rawValue)]';
      for (final line in [
        'cancelsTouchesInView = false',
        'delaysTouchesBegan = false',
        'delaysTouchesEnded = false',
        pencilOnly,
      ]) {
        expect(init, contains(line));
      }
      expect(_all(RegExp(r'state\s*=\s*\.(\w+)'), roll), {'failed'});
      expect(roll, contains('touch.rollAngle'));
    });

    test('hover and roll events are throttled to ≤ 60 Hz', () {
      final interval = RegExp(
        r'static\s+let\s+minInterval\s*:\s*TimeInterval\s*=\s*([\d.]+)',
      ).firstMatch(_code(_wireSwift));
      expect(interval, isNotNull);
      expect(
        double.parse(interval!.group(1)!),
        inInclusiveRange(0.015, 1 / 60),
      );
      expect(
        _body(stream, RegExp(r'func\s+handleHover\s*\(')),
        contains('PencilWire.minInterval'),
      );
      expect(
        _body(_code(_rollSwift), RegExp(r'func\s+report\s*\(')),
        contains('PencilWire.minInterval'),
      );
    });
  });
}
