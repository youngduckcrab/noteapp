// The Swift side of pencil_bridge cannot be compiled in the container (no
// Xcode), so this test compares the Swift sources with the Dart side as text
// (docs/plans/m5-7/01-infra.md 3.3 and 6.12.4).
//
// R2-B1 part: the plugin class name equals `pluginClass` in pubspec.yaml, it
// adopts FlutterPlugin and declares `register(with:)`, and Package.swift and
// the podspec point at the same Sources directory. J12 adds the channel
// names, event types, keys and `#available` guards against the Dart
// constants of src/wire.dart.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _sourcesDir = 'ios/pencil_bridge/Sources/pencil_bridge';
const _pluginSwift = '$_sourcesDir/PencilBridgePlugin.swift';
const _packageSwift = 'ios/pencil_bridge/Package.swift';
const _podspec = 'ios/pencil_bridge.podspec';

/// Swift source without `//` line comments and `/* */` block comments, so a
/// declaration that only appears in a comment does not count.
String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return file.readAsStringSync();
}

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

void main() {
  test('pluginClass is PencilBridgePlugin (iOS only)', () {
    expect(_pluginClass(), 'PencilBridgePlugin');
  });

  test('the Swift plugin class adopts FlutterPlugin and registers', () {
    final swift = _withoutComments(_read(_pluginSwift));
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
    final classes = Directory(_sourcesDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.swift'))
        .where(
          (f) =>
              RegExp(r'\bFlutterPlugin\b')
                  .hasMatch(_withoutComments(f.readAsStringSync())),
        )
        .toList();
    expect(classes, hasLength(1));
  });

  test('Package.swift follows the Flutter plugin SwiftPM layout', () {
    final package = _withoutComments(_read(_packageSwift));
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
    // SwiftPM finds the target's sources at Sources/<target name>/.
    expect(Directory(_sourcesDir).existsSync(), isTrue);
    expect(package, isNot(contains('macOS')));
  });

  test('the podspec builds the same Swift sources for iOS', () {
    final podspec = _read(_podspec);
    expect(podspec, contains("s.name             = 'pencil_bridge'"));
    final sources = RegExp(r"s\.source_files\s*=\s*'([^']+)'")
        .firstMatch(podspec);
    expect(sources, isNotNull);
    expect(sources!.group(1), 'pencil_bridge/Sources/pencil_bridge/**/*.swift');
    // The pattern is relative to ios/ (the podspec's directory).
    expect(
      Directory('ios/${sources.group(1)!.split('/**').first}').existsSync(),
      isTrue,
    );
    expect(podspec, contains("s.platform = :ios, '15.0'"));
    expect(podspec, contains("s.dependency 'Flutter'"));
  });

  test('R2-B1 registration is empty: no channel yet', () {
    final swift = _withoutComments(_read(_pluginSwift));
    // J12 adds the channels; until then main's iOS build only needs the class.
    expect(swift, isNot(contains('FlutterMethodChannel')));
    expect(swift, isNot(contains('FlutterEventChannel')));
  });
}
