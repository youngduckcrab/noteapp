/// Reads the committed native configuration of the app — Android manifest and
/// `build.gradle.kts`, iOS Info.plist, Xcode project, Podfile and xcconfig
/// files — and checks the
/// values INFRA sets (docs/plans/m5-7/01-infra.md 6.10.1, 6.11.1–6.11.4 and
/// appendix B; contract 00-overview 7.4.3 v2.1). The container cannot build
/// Android or iOS, so these files are checked as text (V12):
/// `tool/test/native_config_test.dart` runs [appNativeConfigProblems] on the
/// committed files, and `ws native-reqs` (J1) reads the same [NativeConfig].
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Repo-relative paths of the files [NativeConfig.load] reads.
abstract final class NativeConfigPaths {
  static const String androidManifest =
      'app/android/app/src/main/AndroidManifest.xml';
  static const String androidGradle = 'app/android/app/build.gradle.kts';
  static const String infoPlist = 'app/ios/Runner/Info.plist';
  static const String pbxproj = 'app/ios/Runner.xcodeproj/project.pbxproj';
  static const String podfile = 'app/ios/Podfile';
  static const String debugXcconfig = 'app/ios/Flutter/Debug.xcconfig';
  static const String releaseXcconfig = 'app/ios/Flutter/Release.xcconfig';
}

/// Thrown when a file is missing or cannot be parsed.
final class NativeConfigException implements Exception {
  const NativeConfigException(this.message);

  final String message;

  @override
  String toString() => 'NativeConfigException: $message';
}

const String _androidPrefix = 'android.permission.';
const String _toolsNamespace = 'http://schemas.android.com/tools';

/// The parts of an `AndroidManifest.xml` the checks need. Attribute maps use
/// the qualified names of the file (`android:name`, `tools:node`).
final class AndroidManifestInfo {
  const AndroidManifestInfo({
    required this.permissions,
    required this.removedPermissions,
    required this.application,
    required this.services,
    required this.receivers,
    required this.declaresToolsNamespace,
  });

  /// Parses the manifest text. Throws [NativeConfigException].
  factory AndroidManifestInfo.parse(String text) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(text);
    } on XmlException catch (e) {
      throw NativeConfigException('AndroidManifest.xml: ${e.message}');
    }
    final manifest = document.rootElement;
    if (manifest.name.qualified != 'manifest') {
      throw const NativeConfigException(
        'AndroidManifest.xml: the root element is not <manifest>',
      );
    }
    final permissions = <String>{};
    final removed = <String>{};
    for (final element in manifest.findElements('uses-permission')) {
      final attributes = _attributes(element);
      final name = attributes['android:name'];
      if (name == null) continue;
      if (attributes['tools:node'] == 'remove') {
        removed.add(name);
      } else {
        permissions.add(name);
      }
    }
    final applications = manifest.findElements('application').toList();
    if (applications.length != 1) {
      throw NativeConfigException(
        'AndroidManifest.xml: ${applications.length} <application> elements',
      );
    }
    final application = applications.single;
    Map<String, Map<String, String>> named(String tag) => {
      for (final attributes in application.findElements(tag).map(_attributes))
        ?attributes['android:name']: attributes,
    };
    return AndroidManifestInfo(
      permissions: permissions,
      removedPermissions: removed,
      application: _attributes(application),
      services: named('service'),
      receivers: named('receiver'),
      declaresToolsNamespace:
          _attributes(manifest)['xmlns:tools'] == _toolsNamespace,
    );
  }

  /// `<uses-permission android:name>` without `tools:node="remove"`.
  final Set<String> permissions;

  /// `<uses-permission android:name>` with `tools:node="remove"`.
  final Set<String> removedPermissions;

  /// The attributes of `<application>`.
  final Map<String, String> application;

  /// `<service>` / `<receiver>` under `<application>`: android:name → attributes.
  final Map<String, Map<String, String>> services, receivers;

  /// `xmlns:tools="http://schemas.android.com/tools"` on `<manifest>`.
  final bool declaresToolsNamespace;

  static Map<String, String> _attributes(XmlElement element) => {
    for (final attribute in element.attributes)
      attribute.name.qualified: attribute.value,
  };
}

/// The value of the Gradle setting [key] (`minSdk` or `compileSdk`, also
/// spelled `minSdkVersion` / `compileSdkVersion`) in a `build.gradle` or
/// `build.gradle.kts` text: `minSdk = 24`, `minSdkVersion 21`,
/// `compileSdk(35)`, `compileSdk = flutter.compileSdkVersion`. Comments are
/// ignored; the first setting wins.
///
/// Returns the number as digits, `flutter` when the value is an expression
/// that names Flutter's default (`flutter.minSdkVersion`,
/// `flutterCompileSdkVersion`), any other expression as written, and null
/// when the setting is missing (docs/plans/m5-7/01-infra.md 6.3).
String? gradleSdkValue(String text, String key) {
  final match = RegExp(
    '\\b$key(?:Version)?\\b\\s*(?:=\\s*|\\(\\s*|[ \\t]+)(\\d+|[A-Za-z_][\\w.]*)',
  ).firstMatch(_gradleCode(text));
  if (match == null) return null;
  final value = match.group(1)!;
  if (RegExp(r'^\d+$').hasMatch(value)) return value;
  return value.toLowerCase().contains('flutter') ? gradleFlutterDefault : value;
}

/// [text] without `//` and `/* */` comments.
String _gradleCode(String text) => text
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// What [gradleSdkValue] returns for Flutter's default SDK level.
const String gradleFlutterDefault = 'flutter';

/// The settings of the app's `build.gradle.kts` the checks need: the SDK
/// levels (J1 — NR3, NR4 and the `app:` block of
/// `tool/native_requirements.yaml`; values as [gradleSdkValue] returns them)
/// and the release signing branch (J2 — 6.10.2). Comments are ignored.
final class AndroidGradleInfo {
  const AndroidGradleInfo({
    required this.minSdk,
    required this.compileSdk,
    this.keyPropertiesFile,
    this.createsReleaseSigningOnlyWithKeyProperties = false,
    this.signingProperties = const {},
    this.releaseUsesReleaseKeyElseDebug = false,
  });

  factory AndroidGradleInfo.parse(String text) {
    final code = _gradleCode(text);
    final file = RegExp(
      r'val\s+(\w+)\s*=\s*rootProject\.file\(\s*"([^"]+)"\s*\)',
    ).firstMatch(code);
    final variable = file == null ? null : RegExp.escape(file.group(1)!);
    bool has(String pattern) =>
        variable != null &&
        RegExp(pattern.replaceAll('VAR', variable)).hasMatch(code);
    return AndroidGradleInfo(
      minSdk: gradleSdkValue(text, 'minSdk'),
      compileSdk: gradleSdkValue(text, 'compileSdk'),
      keyPropertiesFile: file?.group(2),
      createsReleaseSigningOnlyWithKeyProperties: has(
        r'if\s*\(\s*VAR\.exists\(\)\s*\)\s*\{\s*create\(\s*"release"\s*\)',
      ),
      signingProperties: {
        for (final m in RegExp(
          r'(\w+)\s*=\s*(?:file\()?\s*\w+\.getProperty\(\s*"(\w+)"\s*\)',
        ).allMatches(code))
          if (m.group(1) == m.group(2)) m.group(2)!,
      },
      releaseUsesReleaseKeyElseDebug: has(
        r'signingConfig\s*=\s*if\s*\(\s*VAR\.exists\(\)\s*\)\s*'
        r'signingConfigs\.getByName\(\s*"release"\s*\)\s*else\s*'
        r'signingConfigs\.getByName\(\s*"debug"\s*\)',
      ),
    );
  }

  final String? minSdk, compileSdk;

  /// The file of `val <name> = rootProject.file("<file>")` (relative to
  /// `app/android/`).
  final String? keyPropertiesFile;

  /// `if (<name>.exists()) { create("release") { … } }`.
  final bool createsReleaseSigningOnlyWithKeyProperties;

  /// `x = <props>.getProperty("x")` settings (`storeFile = file(…)` too).
  final Set<String> signingProperties;

  /// `signingConfig = if (<name>.exists())` the `"release"` signing config,
  /// `else` the `"debug"` one.
  final bool releaseUsesReleaseKeyElseDebug;
}

/// Parses an XML property list into Dart values:
///
/// - `<dict>` → `Map<String, Object>`, `<array>` → `List<Object>`
/// - `<string>`, `<data>`, `<date>` → `String`
/// - `<true/>`, `<false/>` → `bool`; `<integer>` → `int`; `<real>` → `double`
///
/// Throws [NativeConfigException].
Map<String, Object> parsePlist(String text) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(text);
  } on XmlException catch (e) {
    throw NativeConfigException('plist: ${e.message}');
  }
  final root = document.rootElement;
  final top = root.childElements.toList();
  if (root.name.qualified != 'plist' ||
      top.length != 1 ||
      top.single.name.qualified != 'dict') {
    throw const NativeConfigException('plist: expected <plist><dict>');
  }
  return _plistValue(top.single)! as Map<String, Object>;
}

Object? _plistValue(XmlElement element) {
  switch (element.name.qualified) {
    case 'dict':
      final children = element.childElements.toList();
      final map = <String, Object>{};
      for (var i = 0; i < children.length; i += 2) {
        final key = children[i];
        if (key.name.qualified != 'key' || i + 1 >= children.length) {
          throw const NativeConfigException(
            'plist: a <dict> needs key/value pairs',
          );
        }
        map[key.innerText] = _plistValue(children[i + 1])!;
      }
      return map;
    case 'array':
      return [for (final child in element.childElements) _plistValue(child)!];
    case 'string' || 'data' || 'date':
      return element.innerText;
    case 'true':
      return true;
    case 'false':
      return false;
    case 'integer':
      return int.parse(element.innerText.trim());
    case 'real':
      return double.parse(element.innerText.trim());
  }
  throw NativeConfigException('plist: unknown element <${element.name}>');
}

/// Every `IPHONEOS_DEPLOYMENT_TARGET = <v>;` value of a `project.pbxproj`, in
/// file order.
List<String> pbxDeploymentTargets(String pbxproj) => [
  for (final m in RegExp(
    r'IPHONEOS_DEPLOYMENT_TARGET = ([^;\s]+);',
  ).allMatches(pbxproj))
    m.group(1)!,
];

/// The Podfile lines INFRA adds to the Flutter template (6.11.2). Full-line
/// `#` comments are ignored.
final class PodfileInfo {
  const PodfileInfo({
    required this.platformIos,
    required this.iosVersion,
    required this.excludesArmv7,
    required this.setsPodsDeploymentTarget,
    required this.raisesTargetDeploymentTargets,
    required this.callsFlutterAdditionalSettings,
    required this.usesFrameworks,
  });

  factory PodfileInfo.parse(String text) {
    final code = text
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('#'))
        .join('\n');
    String? first(String pattern) =>
        RegExp(pattern, multiLine: true).firstMatch(code)?.group(1);
    bool has(String pattern) => RegExp(pattern, multiLine: true).hasMatch(code);
    return PodfileInfo(
      platformIos: first(r"^\s*platform\s+:ios\s*,\s*'([^']+)'"),
      iosVersion: first(r"^\s*\$iOSVersion\s*=\s*'([^']+)'"),
      excludesArmv7: has(
        r'''build_settings\[["']EXCLUDED_ARCHS\[sdk=\*\]["']\]\s*=\s*["']armv7["']''',
      ),
      setsPodsDeploymentTarget: has(
        r'''build_settings\[["']IPHONEOS_DEPLOYMENT_TARGET["']\]\s*=\s*\$iOSVersion''',
      ),
      raisesTargetDeploymentTargets: has(
        r'''Gem::Version\.new\(\$iOSVersion\)\s*>\s*Gem::Version\.new\(config\.build_settings\[["']IPHONEOS_DEPLOYMENT_TARGET["']\]\)''',
      ),
      callsFlutterAdditionalSettings: has(
        r'^\s*flutter_additional_ios_build_settings\(target\)',
      ),
      usesFrameworks: has(r'^\s*use_frameworks!'),
    );
  }

  /// `platform :ios, '<v>'` (null when missing or commented out).
  final String? platformIos;

  /// `$iOSVersion = '<v>'` (the ML Kit README line).
  final String? iosVersion;

  /// `EXCLUDED_ARCHS[sdk=*] = 'armv7'` in post_install.
  final bool excludesArmv7;

  /// The pods project's `IPHONEOS_DEPLOYMENT_TARGET = $iOSVersion`.
  final bool setsPodsDeploymentTarget;

  /// Each target's deployment target raised to `$iOSVersion`.
  final bool raisesTargetDeploymentTargets;

  /// The Flutter template's `flutter_additional_ios_build_settings(target)`.
  final bool callsFlutterAdditionalSettings;

  /// The Flutter template's `use_frameworks!`.
  final bool usesFrameworks;
}

/// `#include` / `#include?` lines of an xcconfig file, in order.
List<({String path, bool optional})> xcconfigIncludes(String text) => [
  for (final m in RegExp(
    r'^#include(\?)?\s+"([^"]+)"',
    multiLine: true,
  ).allMatches(text))
    (path: m.group(2)!, optional: m.group(1) != null),
];

/// The committed native files of the app, parsed.
final class NativeConfig {
  const NativeConfig({
    required this.manifest,
    required this.androidGradle,
    required this.infoPlist,
    required this.deploymentTargets,
    required this.podfile,
    required this.debugXcconfig,
    required this.releaseXcconfig,
  });

  /// Reads [NativeConfigPaths] under [repoRoot]. Throws
  /// [NativeConfigException] when a file is missing or unreadable.
  factory NativeConfig.load(String repoRoot) {
    String read(String path) {
      final file = File(p.join(repoRoot, path));
      if (!file.existsSync()) throw NativeConfigException('$path is missing');
      return file.readAsStringSync();
    }

    return NativeConfig(
      manifest: AndroidManifestInfo.parse(
        read(NativeConfigPaths.androidManifest),
      ),
      androidGradle: AndroidGradleInfo.parse(
        read(NativeConfigPaths.androidGradle),
      ),
      infoPlist: parsePlist(read(NativeConfigPaths.infoPlist)),
      deploymentTargets: pbxDeploymentTargets(read(NativeConfigPaths.pbxproj)),
      podfile: PodfileInfo.parse(read(NativeConfigPaths.podfile)),
      debugXcconfig: xcconfigIncludes(read(NativeConfigPaths.debugXcconfig)),
      releaseXcconfig: xcconfigIncludes(
        read(NativeConfigPaths.releaseXcconfig),
      ),
    );
  }

  final AndroidManifestInfo manifest;
  final AndroidGradleInfo androidGradle;
  final Map<String, Object> infoPlist;
  final List<String> deploymentTargets;
  final PodfileInfo podfile;
  final List<({String path, bool optional})> debugXcconfig, releaseXcconfig;
}

/// What INFRA sets in the native files (6.10.1, 6.11.1–6.11.4, appendix B).
abstract final class AppNativeExpectations {
  /// App display name on both platforms.
  static const String displayName = '필기노트';

  /// iOS deployment target (ML Kit minimum — contract 7.4.3).
  static const String iosDeploymentTarget = '15.5';

  /// How often the Xcode project sets the deployment target (project,
  /// Runner Debug / Release / Profile — 6.11.1).
  static const int pbxDeploymentTargetCount = 3;

  /// Android permissions the main manifest declares (6.10.1).
  static const Set<String> androidPermissions = {
    '${_androidPrefix}INTERNET',
    '${_androidPrefix}RECORD_AUDIO',
    '${_androidPrefix}FOREGROUND_SERVICE',
    '${_androidPrefix}FOREGROUND_SERVICE_MICROPHONE',
    '${_androidPrefix}POST_NOTIFICATIONS',
  };

  /// Removed in the merge (`tools:node="remove"`): no start on boot.
  static const Set<String> androidRemovedPermissions = {
    '${_androidPrefix}RECEIVE_BOOT_COMPLETED',
  };

  /// flutter_foreground_task's service (its README: do not change the name).
  static const String foregroundService =
      'com.pravera.flutter_foreground_task.service.ForegroundService';

  /// Its attributes (stopWithTask confirmed — 00-review Q7).
  static const Map<String, String> foregroundServiceAttributes = {
    'android:foregroundServiceType': 'microphone',
    'android:exported': 'false',
    'android:stopWithTask': 'true',
  };

  /// flutter_foreground_task's boot receiver, removed in the merge.
  static const String rebootReceiver =
      'com.pravera.flutter_foreground_task.service.RebootReceiver';

  /// Info.plist strings, exactly (contract 7.4.3 v2.1 — 해요체, confirmed).
  static const Map<String, String> iosStrings = {
    'CFBundleDisplayName': displayName,
    'NSMicrophoneUsageDescription': '노트에 녹음을 붙이려면 마이크가 필요해요.',
    'NSPhotoLibraryUsageDescription': '사진을 노트에 넣으려면 사진 보관함에 접근해야 해요.',
    'NSCameraUsageDescription': '사진을 찍어 노트에 넣으려면 카메라가 필요해요.',
  };

  /// Info.plist booleans.
  static const Map<String, bool> iosBooleans = {
    'ITSAppUsesNonExemptEncryption': false,
  };

  /// `UIBackgroundModes` entries (background recording — M6-2).
  static const Set<String> iosBackgroundModes = {'audio'};

  /// The file android.yml writes the signing secrets to, next to
  /// `app/android/settings.gradle.kts` (6.10.2 — gitignored).
  static const String keyProperties = 'key.properties';

  /// The `key.properties` entries the release signing config reads.
  static const Set<String> signingProperties = {
    'storeFile',
    'storePassword',
    'keyAlias',
    'keyPassword',
  };

  /// The CocoaPods include of each Flutter xcconfig (6.11.3), as Flutter's
  /// `addPodsDependencyToFlutterXcconfig` writes it.
  static String podsXcconfig(String mode) =>
      'Pods/Target Support Files/Pods-Runner/Pods-Runner.$mode.xcconfig';
}

/// Every way [config] differs from [AppNativeExpectations], one line each
/// (empty = all set).
List<String> appNativeConfigProblems(NativeConfig config) {
  final problems = <String>[];
  final manifest = config.manifest;

  // --- Android (6.10.1) ---
  if (!manifest.declaresToolsNamespace) {
    problems.add('AndroidManifest: <manifest> lacks xmlns:tools');
  }
  for (final permission in AppNativeExpectations.androidPermissions) {
    if (!manifest.permissions.contains(permission)) {
      problems.add('AndroidManifest: missing <uses-permission $permission>');
    }
  }
  for (final permission in AppNativeExpectations.androidRemovedPermissions) {
    if (!manifest.removedPermissions.contains(permission)) {
      problems.add(
        'AndroidManifest: $permission is not removed (tools:node="remove")',
      );
    }
    if (manifest.permissions.contains(permission)) {
      problems.add('AndroidManifest: $permission is also declared');
    }
  }
  final label = manifest.application['android:label'];
  if (label != AppNativeExpectations.displayName) {
    problems.add(
      'AndroidManifest: android:label is ${label ?? '(none)'}, expected '
      '${AppNativeExpectations.displayName}',
    );
  }
  if (manifest.application['android:allowBackup'] != 'false') {
    problems.add('AndroidManifest: android:allowBackup must be "false" (D20)');
  }
  final service = manifest.services[AppNativeExpectations.foregroundService];
  if (service == null) {
    problems.add(
      'AndroidManifest: missing <service '
      '${AppNativeExpectations.foregroundService}>',
    );
  } else {
    for (final MapEntry(:key, :value)
        in AppNativeExpectations.foregroundServiceAttributes.entries) {
      if (service[key] != value) {
        problems.add(
          'AndroidManifest: ForegroundService $key is '
          '${service[key] ?? '(none)'}, expected $value',
        );
      }
    }
  }
  final receiver = manifest.receivers[AppNativeExpectations.rebootReceiver];
  if (receiver?['tools:node'] != 'remove') {
    problems.add(
      'AndroidManifest: ${AppNativeExpectations.rebootReceiver} is not '
      'removed (tools:node="remove")',
    );
  }

  // --- Android release signing (6.10.2) ---
  final gradle = config.androidGradle;
  const keyProperties = AppNativeExpectations.keyProperties;
  if (gradle.keyPropertiesFile != keyProperties) {
    problems.add(
      'build.gradle.kts: reads ${gradle.keyPropertiesFile ?? '(nothing)'}, '
      'expected rootProject.file("$keyProperties")',
    );
  }
  if (!gradle.createsReleaseSigningOnlyWithKeyProperties) {
    problems.add(
      'build.gradle.kts: create("release") must sit in '
      'if (<$keyProperties file>.exists())',
    );
  }
  for (final name in AppNativeExpectations.signingProperties) {
    if (!gradle.signingProperties.contains(name)) {
      problems.add(
        'build.gradle.kts: the release signing config does not read $name',
      );
    }
  }
  if (!gradle.releaseUsesReleaseKeyElseDebug) {
    problems.add(
      'build.gradle.kts: release must use signingConfigs "release" when '
      '$keyProperties exists, else "debug"',
    );
  }

  // --- iOS Info.plist (6.11.4) ---
  final plist = config.infoPlist;
  for (final MapEntry(:key, :value)
      in AppNativeExpectations.iosStrings.entries) {
    if (plist[key] != value) {
      problems.add(
        'Info.plist: $key is ${plist[key] ?? '(none)'}, expected "$value"',
      );
    }
  }
  for (final MapEntry(:key, :value)
      in AppNativeExpectations.iosBooleans.entries) {
    if (plist[key] != value) {
      problems.add(
        'Info.plist: $key is ${plist[key] ?? '(none)'}, expected $value',
      );
    }
  }
  final modes = plist['UIBackgroundModes'];
  for (final mode in AppNativeExpectations.iosBackgroundModes) {
    if (modes is! List || !modes.contains(mode)) {
      problems.add('Info.plist: UIBackgroundModes lacks $mode');
    }
  }

  // --- Xcode project (6.11.1) ---
  final targets = config.deploymentTargets;
  const target = AppNativeExpectations.iosDeploymentTarget;
  if (targets.length != AppNativeExpectations.pbxDeploymentTargetCount) {
    problems.add(
      'project.pbxproj: IPHONEOS_DEPLOYMENT_TARGET appears '
      '${targets.length} times, expected '
      '${AppNativeExpectations.pbxDeploymentTargetCount}',
    );
  }
  for (final value in targets.toSet()) {
    if (value != target) {
      problems.add(
        'project.pbxproj: IPHONEOS_DEPLOYMENT_TARGET = $value, expected '
        '$target',
      );
    }
  }

  // --- Podfile (6.11.2) ---
  final podfile = config.podfile;
  if (podfile.platformIos != target) {
    problems.add(
      "Podfile: platform :ios is ${podfile.platformIos ?? '(none)'}, "
      "expected '$target'",
    );
  }
  if (podfile.iosVersion != target) {
    problems.add(
      "Podfile: \$iOSVersion is ${podfile.iosVersion ?? '(none)'}, "
      "expected '$target'",
    );
  }
  for (final (ok, what) in [
    (podfile.excludesArmv7, "EXCLUDED_ARCHS[sdk=*] = 'armv7'"),
    (
      podfile.setsPodsDeploymentTarget,
      r'IPHONEOS_DEPLOYMENT_TARGET = $iOSVersion',
    ),
    (
      podfile.raisesTargetDeploymentTargets,
      'per-target deployment target raise',
    ),
    (
      podfile.callsFlutterAdditionalSettings,
      'flutter_additional_ios_build_settings(target)',
    ),
    (podfile.usesFrameworks, 'use_frameworks!'),
  ]) {
    if (!ok) problems.add('Podfile: missing $what');
  }

  // --- xcconfig (6.11.3) ---
  for (final (mode, includes) in [
    ('debug', config.debugXcconfig),
    ('release', config.releaseXcconfig),
  ]) {
    final pods = AppNativeExpectations.podsXcconfig(mode);
    final first = includes.isEmpty ? null : includes.first;
    if (first == null || first.path != pods || !first.optional) {
      problems.add('$mode xcconfig: the first line must be #include? "$pods"');
    }
    if (!includes.any((i) => i.path == 'Generated.xcconfig' && !i.optional)) {
      problems.add('$mode xcconfig: missing #include "Generated.xcconfig"');
    }
  }
  return problems;
}
