// `ws native-reqs` (J1 — docs/plans/m5-7/01-infra.md 4.3.2 and 6.3; contract
// 00-overview 7.4.1 v2.2 C22-03, 7.4.3 v2.1, V12).
//
// The fake plugins (pod only, SwiftPM only, both, `.iOS(.v15)` / `.v16`,
// Gradle kts, Gradle groovy, Dart only) and the fake
// `.flutter-plugins-dependencies` are written to a temp directory by each
// test (tool/test/support/fixture_workspace.dart explains why fixtures are
// not committed). Every rule NR1–NR7 is checked once broken and once clean,
// then the real workspace (when `flutter pub get` wrote
// app/.flutter-plugins-dependencies — CI and the container do).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/native_config.dart';
import '../src/native_reqs.dart';
import '../src/rules.dart';
import 'support/fixture_workspace.dart';

// --- the fixture -------------------------------------------------------------

const String _requirements = '''
app:
  ios_deployment_target: '15.5'
  android_min_sdk: flutter
  android_compile_sdk: flutter
  android_label: Fixture
  android_allow_backup: false
  ios_display_name: Fixture
flutter_defaults: {min_sdk: 24, compile_sdk: 36}
cocoapods_only_allowed: [pod_only]
plugins:
  pod_only: {area: LIBRARY, android_permissions: [INTERNET]}
  spm_only: {area: PDF, ios_plist_keys: [NSMicrophoneUsageDescription]}
  pod_and_spm: {area: PDF, ios_background_modes: [audio]}
  spm_enum: {area: INFRA}
  gradle_kts:
    area: PDF
    android_permissions: [RECORD_AUDIO]
    android_services:
      - {name: a.b.Service, foregroundServiceType: microphone, exported: 'false'}
    android_removed:
      - {tag: receiver, name: a.b.Receiver}
      - {tag: uses-permission, name: android.permission.RECEIVE_BOOT_COMPLETED}
plugins_without_requirements: [gradle_groovy, dart_only]
app_extra:
  android_permissions: [INTERNET]
  ios_plist:
    ITSAppUsesNonExemptEncryption: false
''';

/// The fake plugin files, by path under the fixture directory.
const Map<String, String> _pluginFiles = {
  'plugins/pod_only/ios/pod_only.podspec': '''
Pod::Spec.new do |s|
  s.name = 'pod_only'
  # s.platform = :ios, '99.0'
  s.platform = :ios, '15.0'
  s.ios.deployment_target = '15.5'
end
''',
  'plugins/spm_only/ios/spm_only/Package.swift': '''
// swift-tools-version: 5.9
let package = Package(
  name: "spm_only",
  // platforms: [.iOS("99.0")],
  platforms: [.iOS("13.0")],
)
''',
  'plugins/pod_and_spm/darwin/pod_and_spm.podspec': '''
Pod::Spec.new do |spec|
  spec.ios.deployment_target = "12.0"
  spec.osx.deployment_target = "10.14"
end
''',
  'plugins/pod_and_spm/darwin/pod_and_spm/Package.swift': '''
let package = Package(name: "pod_and_spm", platforms: [.iOS("12.0"), .macOS("10.14")])
''',
  'plugins/spm_enum/ios/spm_enum.podspec': '''
Pod::Spec.new do |s|
  s.platform = :ios, '15.0'
end
''',
  'plugins/spm_enum/ios/spm_enum/Package.swift': '''
let package = Package(name: "spm_enum", platforms: [.iOS(.v15)])
''',
  'plugins/gradle_kts/android/build.gradle.kts': '''
android {
    namespace = "dev.fixture.gradle_kts"
    compileSdk = flutter.compileSdkVersion
    defaultConfig {
        minSdk = 24
    }
}
''',
  'plugins/gradle_groovy/android/build.gradle': '''
android {
    // compileSdk 99 is the next one
    compileSdk 35
    defaultConfig {
        /* minSdkVersion 30 */
        minSdkVersion 21
    }
}
''',
  'plugins/dart_only/lib/dart_only.dart': '',
};

const List<String> _graph = [
  'dart_only',
  'fixture_app',
  'fixture_web',
  'gradle_groovy',
  'gradle_kts',
  'pod_and_spm',
  'pod_only',
  'spm_enum',
  'spm_only',
];

/// `.flutter-plugins-dependencies` with relative paths (Flutter writes
/// absolute ones; both resolve).
String _dependenciesJson({
  List<String> ios = const ['pod_only', 'spm_only', 'pod_and_spm', 'spm_enum'],
  List<String> android = const ['gradle_kts', 'gradle_groovy', 'dart_only'],
  List<String> graph = _graph,
}) {
  Map<String, Object?> plugin(String name) => {
    'name': name,
    'path': 'plugins/$name/',
    'native_build': name != 'dart_only',
    'dependencies': <String>[],
    'dev_dependency': false,
  };
  return jsonEncode({
    'info': 'fixture',
    'plugins': {
      'ios': [for (final name in ios) plugin(name)],
      'android': [for (final name in android) plugin(name)],
      'web': [plugin('fixture_web')],
    },
    'dependencyGraph': [
      for (final name in graph) {'name': name, 'dependencies': <String>[]},
    ],
  });
}

const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.RECORD_AUDIO"/>
  <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" tools:node="remove"/>
  <application android:label="Fixture" android:allowBackup="false">
    <service android:name="a.b.Service" android:foregroundServiceType="microphone"
        android:exported="false"/>
    <receiver android:name="a.b.Receiver" tools:node="remove"/>
  </application>
</manifest>
''';

const Map<String, Object> _plist = {
  'CFBundleDisplayName': 'Fixture',
  'NSMicrophoneUsageDescription': 'mic',
  'UIBackgroundModes': ['audio'],
  'ITSAppUsesNonExemptEncryption': false,
};

const String _podfile = r'''
platform :ios, '15.5'
$iOSVersion = '15.5'
''';

const String _gradle = '''
android {
    compileSdk = flutter.compileSdkVersion
    defaultConfig { minSdk = flutter.minSdkVersion }
}
''';

NativeConfig _config({
  String manifest = _manifest,
  Map<String, Object> plist = _plist,
  List<String> targets = const ['15.5', '15.5', '15.5'],
  String podfile = _podfile,
  String gradle = _gradle,
}) => NativeConfig(
  manifest: AndroidManifestInfo.parse(manifest),
  androidGradle: AndroidGradleInfo.parse(gradle),
  infoPlist: plist,
  deploymentTargets: targets,
  podfile: PodfileInfo.parse(podfile),
  debugXcconfig: const [],
  releaseXcconfig: const [],
);

/// A temp directory with [_pluginFiles] (each [edits] entry replaces a file;
/// null deletes it).
final class _Fixture {
  _Fixture([Map<String, String?> edits = const {}])
    : dir = Directory.systemTemp.createTempSync('native_reqs_test_') {
    final files = {..._pluginFiles, ...edits};
    for (final MapEntry(:key, :value) in files.entries) {
      if (value == null) continue;
      File(p.join(dir.path, key))
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
  }

  final Directory dir;

  FlutterPluginsDependencies dependencies({
    List<String>? ios,
    List<String>? android,
    List<String>? graph,
  }) => FlutterPluginsDependencies.parse(
    _dependenciesJson(
      ios: ios ?? const ['pod_only', 'spm_only', 'pod_and_spm', 'spm_enum'],
      android: android ?? const ['gradle_kts', 'gradle_groovy', 'dart_only'],
      graph: graph ?? _graph,
    ),
    baseDirectory: dir.path,
  );

  NativeReqsReport check({
    String requirements = _requirements,
    FlutterPluginsDependencies? dependencies,
    List<String> pluginPackages = _graph,
    NativeConfig? config,
    ({int minSdk, int compileSdk})? flutterDefaults,
    Iterable<String> appProblems = const [],
  }) => checkNativeRequirements(
    requirements: NativeRequirements.parse(requirements),
    dependencies: dependencies ?? this.dependencies(),
    pluginPackages: pluginPackages,
    config: config ?? _config(),
    flutterDefaults: flutterDefaults,
    appProblems: appProblems,
  );

  void dispose() => dir.deleteSync(recursive: true);
}

/// The findings of [report] as `rule: message` (warnings marked).
List<String> _findings(NativeReqsReport report) => [
  for (final f in report.findings) '$f',
];

void main() {
  late _Fixture fixture;
  _Fixture make([Map<String, String?> edits = const {}]) {
    fixture = _Fixture(edits);
    addTearDown(fixture.dispose);
    return fixture;
  }

  group('parsers', () {
    test('compareVersions: dotted numbers, missing parts are 0', () {
      expect(compareVersions('15.5', '16'), -1);
      expect(compareVersions('16', '16.0'), 0);
      expect(compareVersions('16.1', '16.0.9'), 1);
      expect(compareVersions('12.0', '9.3'), 1);
      expect(() => compareVersions('15.x', '1'), throwsFormatException);
    });

    test('podspecIosMinimum: s.platform / ios.deployment_target, the larger '
        'one, comment lines ignored', () {
      expect(podspecIosMinimum("  s.platform = :ios, '12.0'"), '12.0');
      expect(podspecIosMinimum('spec.ios.deployment_target = "15.5"'), '15.5');
      expect(
        podspecIosMinimum(
          "s.platform = :ios, '15.0'\ns.ios.deployment_target = '15.5'",
        ),
        '15.5',
      );
      expect(
        podspecIosMinimum(
          "  # s.platform = :ios, '99.0'\ns.platform = :ios, '13.0'",
        ),
        '13.0',
      );
      expect(podspecIosMinimum("s.osx.deployment_target = '10.14'"), isNull);
    });

    test('swiftPackageIosMinimum: "x", .vNN, .vNN_M, comments ignored', () {
      expect(swiftPackageIosMinimum('platforms: [.iOS("13.0")]'), '13.0');
      expect(swiftPackageIosMinimum('platforms: [.iOS(.v16)]'), '16.0');
      expect(swiftPackageIosMinimum('platforms: [.iOS(.v16_4)]'), '16.4');
      expect(
        swiftPackageIosMinimum(
          '// .iOS("99.0")\nplatforms: [ .iOS( "12.0" ) ]',
        ),
        '12.0',
      );
      expect(swiftPackageIosMinimum('platforms: [.macOS("10.14")]'), isNull);
    });

    test('gradleSdkValue: kts, groovy, parentheses, Flutter defaults, '
        'comments', () {
      expect(gradleSdkValue('minSdk = 24', 'minSdk'), '24');
      expect(gradleSdkValue('    minSdkVersion 21', 'minSdk'), '21');
      expect(gradleSdkValue('compileSdk 35', 'compileSdk'), '35');
      expect(gradleSdkValue('compileSdkVersion(34)', 'compileSdk'), '34');
      expect(
        gradleSdkValue('compileSdk = flutter.compileSdkVersion', 'compileSdk'),
        'flutter',
      );
      expect(
        gradleSdkValue('minSdk = flutter.minSdkVersion', 'minSdk'),
        'flutter',
      );
      // android_file_picker 2.1.3: a local val read from the Flutter
      // extension; the `intProperty("compileSdkVersion")` string is not a
      // setting.
      expect(
        gradleSdkValue(
          'val flutterCompileSdkVersion = flutterExtension.intProperty('
              '"compileSdkVersion")\n'
              'android {\n  compileSdk = flutterCompileSdkVersion\n}',
          'compileSdk',
        ),
        'flutter',
      );
      expect(
        gradleSdkValue(
          '// compileSdk 99\n/* compileSdk 98 */\ncompileSdk = 36',
          'compileSdk',
        ),
        '36',
      );
      expect(
        gradleSdkValue('compileSdk rootProject.ext.sdk', 'compileSdk'),
        'rootProject.ext.sdk',
      );
      expect(gradleSdkValue('targetSdk = 36', 'minSdk'), isNull);
      expect(gradleSdkValue('minSdkPreview = "x"', 'minSdk'), isNull);
    });

    test('flutterGradleDefaults: FlutterExtension.kt values', () {
      expect(
        flutterGradleDefaults('''
    /** Sets the compileSdkVersion used by default in Flutter app projects. */
    val compileSdkVersion: Int = 36
    val minSdkVersion: Int = 24
'''),
        (minSdk: 24, compileSdk: 36),
      );
      expect(flutterGradleDefaults('val minSdkVersion: Int = 24'), isNull);
    });

    test('NativeRequirements.parse: values, prefixes, component tags', () {
      final r = NativeRequirements.parse(_requirements);
      expect(r.app.iosDeploymentTarget, '15.5');
      expect(r.app.androidMinSdk, 'flutter');
      expect(r.app.androidAllowBackup, isFalse);
      expect((r.flutterMinSdk, r.flutterCompileSdk), (24, 36));
      expect(r.cocoapodsOnlyAllowed, {'pod_only'});
      expect(r.listed, {..._pluginFiles.keys.map((k) => k.split('/')[1])});
      final kts = r.plugins['gradle_kts']!;
      expect(kts.androidPermissions, ['android.permission.RECORD_AUDIO']);
      expect(kts.androidServices.single.tag, 'service');
      expect(kts.androidServices.single.attributes, {
        'foregroundServiceType': 'microphone',
        'exported': 'false',
      });
      expect(
        [for (final c in kts.androidRemoved) (c.tag, c.name)],
        [
          ('receiver', 'a.b.Receiver'),
          ('uses-permission', 'android.permission.RECEIVE_BOOT_COMPLETED'),
        ],
      );
      expect(
        kts.summary,
        'RECORD_AUDIO, service Service, remove Receiver, remove '
        'RECEIVE_BOOT_COMPLETED',
      );
      expect(r.appExtraAndroidPermissions, ['android.permission.INTERNET']);
      expect(r.appExtraIosPlist, {'ITSAppUsesNonExemptEncryption': false});
    });

    test('NativeRequirements.parse: format errors name the key', () {
      for (final (edit, message) in [
        (
          _requirements.replaceFirst('  spm_enum: {area: INFRA}', '  x: {}'),
          'plugins.x.area',
        ),
        (
          _requirements.replaceFirst(
            '  spm_enum: {area: INFRA}',
            '  spm_enum: {area: INFRA, ios_plist: [a]}',
          ),
          'unknown key `ios_plist`',
        ),
        (
          _requirements.replaceFirst(
            '[gradle_groovy,',
            '[spm_enum, gradle_groovy,',
          ),
          'both plugins and plugins_without_requirements: spm_enum',
        ),
        (
          _requirements.replaceFirst(
            'android_min_sdk: flutter',
            'android_min_sdk: x',
          ),
          'app.android_min_sdk',
        ),
        (
          _requirements.replaceFirst('{tag: receiver,', '{tag: activity,'),
          'unknown tag `activity`',
        ),
        (
          _requirements.replaceFirst("'15.5'", "'15.x'"),
          'app.ios_deployment_target',
        ),
        (
          _requirements.replaceFirst('flutter_defaults:', 'other:'),
          'flutter_defaults',
        ),
        ('- a', 'not a YAML map'),
      ]) {
        expect(
          () => NativeRequirements.parse(edit),
          throwsA(
            isA<NativeReqsException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
          reason: message,
        );
      }
    });

    test(
      'FlutterPluginsDependencies: paths, native_build, dependencyGraph',
      () {
        final deps = make().dependencies();
        expect(deps.ios.map((x) => x.name), [
          'pod_only',
          'spm_only',
          'pod_and_spm',
          'spm_enum',
        ]);
        expect(
          deps.ios.first.path,
          p.join(fixture.dir.path, 'plugins', 'pod_only'),
        );
        expect(deps.android.last.nativeBuild, isFalse);
        expect(deps.dependencyGraph, _graph.toSet());
        final absolute = FlutterPluginsDependencies.parse(
          jsonEncode({
            'plugins': {
              'ios': [
                {'name': 'a', 'path': '/abs/a/', 'native_build': true},
              ],
            },
            'dependencyGraph': <Object>[],
          }),
          baseDirectory: '/elsewhere',
        );
        expect(absolute.ios.single.path, '/abs/a');
        expect(absolute.android, isEmpty);
        for (final bad in [
          '{',
          '[]',
          '{"plugins": {}}',
          '{"plugins": {"ios": [{"name": "a"}]}, "dependencyGraph": []}',
        ]) {
          expect(
            () => FlutterPluginsDependencies.parse(bad, baseDirectory: '/'),
            throwsA(isA<NativeReqsException>()),
            reason: bad,
          );
        }
      },
    );

    test('PluginNativeInfo.read: the six kinds of plugin', () {
      final dir = make().dir.path;
      PluginNativeInfo read(String name) =>
          PluginNativeInfo.read(name, p.join(dir, 'plugins', name));
      final pod = read('pod_only');
      expect((pod.hasPodspec, pod.podIos), (true, '15.5'));
      expect((pod.hasSwiftPackage, pod.hasGradle), (false, false));
      final spm = read('spm_only');
      expect((spm.hasPodspec, spm.hasSwiftPackage), (false, true));
      expect(spm.swiftPackageIos, '13.0');
      final both = read('pod_and_spm');
      expect((both.podIos, both.swiftPackageIos), ('12.0', '12.0'));
      final enumeration = read('spm_enum');
      expect(enumeration.swiftPackageIos, '15.0');
      expect(enumeration.iosMinimum, '15.0');
      final kts = read('gradle_kts');
      expect((kts.androidMinSdk, kts.androidCompileSdk), ('24', 'flutter'));
      expect(kts.hasPodspec, isFalse);
      final groovy = read('gradle_groovy');
      expect((groovy.androidMinSdk, groovy.androidCompileSdk), ('21', '35'));
      expect(
        () => PluginNativeInfo.read('gone', p.join(dir, 'plugins', 'gone')),
        throwsA(isA<NativeReqsException>()),
      );
    });
  });

  group('the clean fixture', () {
    test('no finding; app values and the CocoaPods-only list', () {
      final report = make().check();
      expect(_findings(report), isEmpty);
      expect(report.appIos, '15.5');
      expect((report.appMinSdk, report.appCompileSdk), (24, 36));
      expect(report.appMinSdkNote, ' (flutter — flutter_defaults)');
      expect(report.cocoapodsOnly, ['pod_only']);
      expect(report.rows.map((r) => r.name), [
        'dart_only',
        'gradle_groovy',
        'gradle_kts',
        'pod_and_spm',
        'pod_only',
        'spm_enum',
        'spm_only',
      ]);
      expect(report.rows.first.info, isNull, reason: 'native_build: false');
    });

    test('format: table, app line, summary', () {
      final lines = const LineSplitter().convert(make().check().format());
      expect(
        lines.first,
        'plugin        ios(pod) ios(spm) minSdk compileSdk requirements',
      );
      expect(
        lines,
        contains(
          'dart_only     -        -        -      -          (Dart only) -',
        ),
      );
      expect(
        lines,
        contains(
          'gradle_kts    -        no       24     flutter    RECORD_AUDIO, '
          'service Service, remove Receiver, remove RECEIVE_BOOT_COMPLETED',
        ),
      );
      expect(
        lines,
        contains('pod_only      15.5     no       -      -          INTERNET'),
      );
      expect(
        lines,
        contains(
          'spm_only      -        13.0     -      -          '
          'NSMicrophoneUsageDescription',
        ),
      );
      expect(
        lines[lines.length - 2],
        'app: ios 15.5 · minSdk 24 (flutter — flutter_defaults) · compileSdk '
        '36 (flutter — flutter_defaults) · CocoaPods-only: pod_only',
      );
      expect(
        lines.last,
        'ws native-reqs: 7 plugin(s), 0 violation(s), 0 warning(s)',
      );
    });
  });

  group('every rule — broken once', () {
    test('NR1: an unlisted iOS / Android plugin is a violation, a listed but '
        'unresolved name a warning', () {
      final f = make({'plugins/new_plugin/android/build.gradle': 'minSdk 21'});
      final report = f.check(
        dependencies: f.dependencies(
          android: ['gradle_kts', 'gradle_groovy', 'dart_only', 'new_plugin'],
          graph: [..._graph, 'new_plugin'],
        ),
        pluginPackages: [..._graph, 'new_plugin'],
      );
      expect(_findings(report), [
        'NR1: new_plugin is an iOS / Android plugin of the app but tool/native_requirements.yaml does not list it (plugins or plugins_without_requirements)',
      ]);
      final stale = f.check(
        requirements: _requirements.replaceFirst(
          '[gradle_groovy, dart_only]',
          '[gradle_groovy, dart_only, gone]',
        ),
      );
      expect(_findings(stale), [
        'NR1 warning: tool/native_requirements.yaml lists gone, which the app does not resolve for iOS or Android',
      ]);
      expect(stale.violations, isEmpty);
    });

    test('NR2: a plugin above the deployment target (.iOS(.v16) > 15.5)', () {
      final report = make({
        'plugins/spm_enum/ios/spm_enum/Package.swift':
            'let package = Package(platforms: [.iOS(.v16)])',
      }).check();
      expect(_findings(report), [
        'NR2: spm_enum needs iOS 16.0, the app targets 15.5',
      ]);
      // The pod value counts too, and the lowest Xcode target is the app's.
      final pod = fixture.check(config: _config(targets: ['15.5', '15.0']));
      expect(
        _findings(pod),
        contains(
          'NR2: pod_only needs iOS 15.5, the app '
          'targets 15.0',
        ),
      );
    });

    test('NR3: a plugin minSdk above the app (also against '
        'FlutterExtension.kt values)', () {
      final report = make({
        'plugins/gradle_kts/android/build.gradle.kts': 'minSdk = 26',
      }).check();
      expect(_findings(report), [
        'NR3: gradle_kts needs minSdk 26, the app has 24',
      ]);
      final lower = fixture.check(
        flutterDefaults: (minSdk: 23, compileSdk: 36),
      );
      expect(_findings(lower), [
        'NR3: gradle_kts needs minSdk 26, the app has 23',
      ]);
      expect(lower.appMinSdkNote, ' (flutter — FlutterExtension.kt)');
      // A number in the app's build.gradle.kts wins over the default — and
      // NR7 reports that it is not Flutter's default.
      final numbered = fixture.check(
        config: _config(
          gradle: 'minSdk = 26\ncompileSdk = flutter.compileSdkVersion',
        ),
      );
      expect(_findings(numbered), [
        'NR7: build.gradle.kts: minSdk is 26, expected flutter.minSdkVersion',
      ]);
      expect((numbered.appMinSdk, numbered.appMinSdkNote), (26, ''));
    });

    test('NR4: a plugin compileSdk above the app is a warning only', () {
      final report = make({
        'plugins/gradle_groovy/android/build.gradle':
            'compileSdk 37\nminSdkVersion 21',
      }).check();
      expect(_findings(report), [
        'NR4 warning: gradle_groovy needs compileSdk 37, the app has 36',
      ]);
      expect(report.violations, isEmpty);
      expect(report.format(), endsWith('0 violation(s), 1 warning(s)\n'));
    });

    test('NR5: a CocoaPods-only plugin not allowed, an allowed one that is '
        'not CocoaPods-only', () {
      final report = make({
        'plugins/pod_and_spm/darwin/pod_and_spm/Package.swift': null,
      }).check();
      expect(report.cocoapodsOnly, ['pod_and_spm', 'pod_only']);
      expect(_findings(report), [
        'NR5: pod_and_spm has no Package.swift (CocoaPods only) and is not in cocoapods_only_allowed',
      ]);
      final stale = fixture.check(
        requirements: _requirements.replaceFirst(
          'cocoapods_only_allowed: [pod_only]',
          'cocoapods_only_allowed: [pod_only, pod_and_spm, spm_only]',
        ),
      );
      expect(_findings(stale), [
        'NR5: cocoapods_only_allowed lists spm_only, which is not a CocoaPods-only iOS plugin of the app',
      ]);
    });

    test('NR6: plugin_packages ≠ dependencyGraph — missing and extra on '
        'separate lines (web-only and app-facing names count)', () {
      final f = make();
      final report = f.check(
        pluginPackages: [
          for (final name in _graph)
            if (name != 'fixture_web' && name != 'fixture_app') name,
          'old_plugin',
        ],
      );
      expect(_findings(report), [
        'NR6: plugin_packages (tool/workspace_rules.yaml) lacks fixture_app, fixture_web (in dependencyGraph)',
        'NR6: plugin_packages (tool/workspace_rules.yaml) has old_plugin, not in dependencyGraph',
      ]);
    });

    test('NR7: each requirement kind, one line each', () {
      final f = make();
      String drop(String text, String line) {
        expect(_manifest, contains(line));
        return text.replaceFirst(line, '');
      }

      for (final (what, config, expected) in [
        (
          'plugin permission',
          _config(
            manifest: drop(
              _manifest,
              '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
            ),
          ),
          'AndroidManifest: missing <uses-permission '
              'android.permission.RECORD_AUDIO>',
        ),
        (
          // pod_only and app_extra both ask for it: one line.
          'shared permission',
          _config(
            manifest: drop(
              _manifest,
              '<uses-permission android:name="android.permission.INTERNET"/>',
            ),
          ),
          'AndroidManifest: missing <uses-permission '
              'android.permission.INTERNET>',
        ),
        (
          'service attribute',
          _config(
            manifest: _manifest.replaceFirst(
              'android:exported="false"',
              'android:exported="true"',
            ),
          ),
          'AndroidManifest: Service android:exported is true, expected false',
        ),
        (
          'service',
          _config(manifest: _manifest.replaceFirst('a.b.Service', 'a.b.Other')),
          'AndroidManifest: missing <service a.b.Service>',
        ),
        (
          'removed receiver',
          _config(
            manifest: _manifest.replaceFirst(
              '<receiver android:name="a.b.Receiver" tools:node="remove"/>',
              '<receiver android:name="a.b.Receiver"/>',
            ),
          ),
          'AndroidManifest: a.b.Receiver is not removed (tools:node="remove")',
        ),
        (
          'removed permission',
          _config(
            manifest: drop(
              _manifest,
              '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" tools:node="remove"/>',
            ),
          ),
          'AndroidManifest: android.permission.RECEIVE_BOOT_COMPLETED is not '
              'removed (tools:node="remove")',
        ),
        (
          'plist key',
          _config(plist: {..._plist}..['NSMicrophoneUsageDescription'] = ' '),
          'Info.plist: NSMicrophoneUsageDescription is missing or empty '
              '(needed by spm_only)',
        ),
        (
          'background mode',
          _config(plist: {..._plist}..['UIBackgroundModes'] = <Object>[]),
          'Info.plist: UIBackgroundModes lacks audio',
        ),
        (
          'app_extra plist',
          _config(plist: {..._plist}..['ITSAppUsesNonExemptEncryption'] = true),
          'Info.plist: ITSAppUsesNonExemptEncryption is true, expected false',
        ),
        (
          'display name',
          _config(plist: {..._plist}..remove('CFBundleDisplayName')),
          'Info.plist: CFBundleDisplayName is (none), expected "Fixture"',
        ),
        (
          'label',
          _config(
            manifest: _manifest.replaceFirst(
              'android:label="Fixture"',
              'android:label="x"',
            ),
          ),
          'AndroidManifest: android:label is x, expected Fixture',
        ),
        (
          'allowBackup',
          _config(
            manifest: _manifest.replaceFirst('android:allowBackup="false"', ''),
          ),
          'AndroidManifest: android:allowBackup must be "false" (D20)',
        ),
        (
          'Xcode target',
          _config(targets: ['15.5', '16.0']),
          'project.pbxproj: IPHONEOS_DEPLOYMENT_TARGET = 16.0, expected 15.5',
        ),
        (
          'Podfile platform',
          _config(podfile: r"$iOSVersion = '15.5'"),
          "Podfile: platform :ios is (none), expected '15.5'",
        ),
        (
          'compileSdk',
          _config(gradle: 'compileSdk = 35\nminSdk = flutter.minSdkVersion'),
          'build.gradle.kts: compileSdk is 35, expected '
              'flutter.compileSdkVersion',
        ),
      ]) {
        expect(_findings(f.check(config: config)), [
          'NR7: $expected',
        ], reason: what);
        expect(
          nativeRequirementProblems(
            NativeRequirements.parse(_requirements),
            config,
          ),
          [expected],
          reason: what,
        );
      }
    });

    test('NR7: appProblems are added once (same wording = one line)', () {
      final report = make().check(
        config: _config(
          manifest: _manifest.replaceFirst(
            '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
            '',
          ),
        ),
        appProblems: [
          'Podfile: missing use_frameworks!',
          'AndroidManifest: missing <uses-permission android.permission.RECORD_AUDIO>',
        ],
      );
      expect(_findings(report), [
        'NR7: AndroidManifest: missing <uses-permission android.permission.RECORD_AUDIO>',
        'NR7: Podfile: missing use_frameworks!',
      ]);
    });
  });

  group('the real workspace', () {
    final depsPath = p.join(repoRoot, NativeReqsPaths.pluginsDependencies);
    final skip = File(depsPath).existsSync()
        ? null
        : '$depsPath is missing (flutter pub get)';

    test('no violation, no warning; CocoaPods-only = the two ML Kit plugins; '
        'plugin_packages = dependencyGraph', () {
      final config = NativeConfig.load(repoRoot);
      final rules = WorkspaceRules.load(realRulesPath);
      final dependencies = FlutterPluginsDependencies.load(depsPath);
      final report = checkNativeRequirements(
        requirements: NativeRequirements.load(
          p.join(repoRoot, NativeReqsPaths.requirements),
        ),
        dependencies: dependencies,
        pluginPackages: rules.pluginPackages,
        config: config,
        appProblems: appNativeConfigProblems(config),
      );
      expect(_findings(report), isEmpty, reason: report.format());
      expect(report.cocoapodsOnly, [
        'google_mlkit_commons',
        'google_mlkit_digital_ink_recognition',
      ]);
      expect(rules.pluginPackages.toSet(), dependencies.dependencyGraph);
      expect(rules.pluginPackages, hasLength(55));
      expect(report.appIos, '16.0');
    }, skip: skip);

    test('`ws native-reqs` exits 0 with the table', () async {
      final out = StringBuffer(), err = StringBuffer();
      final code = await runWs([
        'native-reqs',
      ], context: WsContext(root: repoRoot, out: out, err: err));
      expect(code, 0, reason: '$out$err');
      final text = '$out';
      expect(text, startsWith('plugin '));
      expect(
        text,
        contains(
          'app: ios 16.0 · minSdk 24 (flutter — FlutterExtension.kt) · '
          'compileSdk 36 (flutter — FlutterExtension.kt) · CocoaPods-only: '
          'google_mlkit_commons, google_mlkit_digital_ink_recognition',
        ),
      );
      expect(text, contains(', 0 violation(s), 0 warning(s)'));
    }, skip: skip);
  });

  group('`ws native-reqs` on a copy of the repo files', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('native_reqs_cli_');
      addTearDown(() => root.deleteSync(recursive: true));
      for (final path in [
        NativeConfigPaths.androidManifest,
        NativeConfigPaths.androidGradle,
        NativeConfigPaths.infoPlist,
        NativeConfigPaths.pbxproj,
        NativeConfigPaths.podfile,
        NativeConfigPaths.debugXcconfig,
        NativeConfigPaths.releaseXcconfig,
        NativeReqsPaths.requirements,
        'tool/workspace_rules.yaml',
      ]) {
        File(p.join(root.path, path))
          ..createSync(recursive: true)
          ..writeAsBytesSync(File(p.join(repoRoot, path)).readAsBytesSync());
      }
    });

    Future<(int, String, String)> run() async {
      final out = StringBuffer(), err = StringBuffer();
      final code = await runWs([
        'native-reqs',
      ], context: WsContext(root: root.path, out: out, err: err));
      return (code, '$out', '$err');
    }

    test('no .flutter-plugins-dependencies → exit 3 with the hint', () async {
      final (code, _, err) = await run();
      expect(code, environmentExitCode);
      expect(err, contains('flutter pub get'));
    });

    test('an unlisted plugin → exit 1 with the NR1 line', () async {
      Directory(p.join(root.path, 'plugins', 'new_plugin'))
          .createSync(recursive: true);
      File(p.join(root.path, NativeReqsPaths.pluginsDependencies))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'plugins': {
              'android': [
                {
                  'name': 'new_plugin',
                  'path': '../plugins/new_plugin/',
                  'native_build': false,
                },
              ],
            },
            'dependencyGraph': [
              {'name': 'new_plugin'},
            ],
          }),
        );
      final (code, out, _) = await run();
      expect(code, 1, reason: out);
      expect(
        out,
        contains(
          'NR1: new_plugin is an iOS / Android plugin of the app but '
          'tool/native_requirements.yaml does not list it',
        ),
      );
      expect(
        out,
        contains(
          'NR6: plugin_packages (tool/workspace_rules.yaml) '
          'lacks new_plugin',
        ),
      );
    });

    test('a broken requirements file → exit 3', () async {
      File(p.join(root.path, NativeReqsPaths.requirements))
          .writeAsStringSync('app: 1\n');
      File(p.join(root.path, NativeReqsPaths.pluginsDependencies))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"plugins": {}, "dependencyGraph": []}');
      final (code, _, err) = await run();
      expect(code, environmentExitCode);
      expect(err, contains('native_requirements.yaml: `app` must be a map'));
    });
  });
}
