/// `ws native-reqs` — the native requirements of every plugin the app pulls
/// in, against the app's own native settings (docs/plans/m5-7/01-infra.md
/// 4.3.2 and 6.3; contract 00-overview 7.4.1 v2.2 and 7.4.3 v2.1, V12).
///
/// Inputs: `app/.flutter-plugins-dependencies` (written by `flutter pub
/// get`), `tool/native_requirements.yaml`, `plugin_packages` of
/// `tool/workspace_rules.yaml`, the committed native files ([NativeConfig])
/// and Flutter's default SDK levels (`FlutterExtension.kt` of the Flutter
/// in use, else `flutter_defaults` of the requirements file). Each plugin's
/// podspec, `Package.swift` and `android/build.gradle(.kts)` are read as
/// text.
///
/// | rule | finding | kind |
/// |---|---|---|
/// | NR1 | an iOS / Android plugin of the app is not listed in the requirements file | violation |
/// | NR2 | a plugin's iOS minimum is above the app's deployment target | violation |
/// | NR3 | a plugin's minSdk is above the app's | violation |
/// | NR4 | a plugin's compileSdk is above the app's | warning |
/// | NR5 | the CocoaPods-only iOS plugins differ from `cocoapods_only_allowed` | violation |
/// | NR6 | `plugin_packages` differs from the `dependencyGraph` names | violation |
/// | NR7 | a listed requirement is missing from the app's native files | violation |
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'native_config.dart';

/// Repo-relative paths `ws native-reqs` reads (besides [NativeConfigPaths]).
abstract final class NativeReqsPaths {
  static const String requirements = 'tool/native_requirements.yaml';
  static const String pluginsDependencies = 'app/.flutter-plugins-dependencies';

  /// Under the Flutter SDK root: the default SDK levels of Flutter apps.
  static const String flutterExtension =
      'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt';
}

/// Thrown when an input is missing or malformed (`ws` exit code 3).
final class NativeReqsException implements Exception {
  const NativeReqsException(this.message);

  final String message;

  @override
  String toString() => 'NativeReqsException: $message';
}

const String _permissionPrefix = 'android.permission.';

/// `RECORD_AUDIO` → `android.permission.RECORD_AUDIO`; names with a dot stay.
String androidPermissionName(String name) =>
    name.contains('.') ? name : '$_permissionPrefix$name';

/// Compares dotted version numbers (`15.5` < `16` = `16.0`). Throws
/// [FormatException] for anything else.
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(v)) {
      throw FormatException('not a version number: $v');
    }
    return [for (final part in v.split('.')) int.parse(part)];
  }

  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

// --- tool/native_requirements.yaml ------------------------------------------

/// The `app:` block — the app's own native settings.
final class AppRequirements {
  const AppRequirements({
    required this.iosDeploymentTarget,
    required this.androidMinSdk,
    required this.androidCompileSdk,
    required this.androidLabel,
    required this.androidAllowBackup,
    required this.iosDisplayName,
  });

  final String iosDeploymentTarget;

  /// Digits, or [gradleFlutterDefault] (Flutter's default).
  final String androidMinSdk, androidCompileSdk;
  final String androidLabel;
  final bool androidAllowBackup;
  final String iosDisplayName;
}

/// A `<service>` / `<receiver>` / `<uses-permission>` of the main manifest.
final class AndroidComponent {
  const AndroidComponent({
    required this.tag,
    required this.name,
    this.attributes = const {},
  });

  /// `service`, `receiver` or `uses-permission`.
  final String tag;

  /// `android:name` (full class or permission name).
  final String name;

  /// Expected attributes without the `android:` prefix.
  final Map<String, String> attributes;

  /// The last part of [name] (`…service.ForegroundService` → `ForegroundService`).
  String get shortName => name.split('.').last;
}

/// What one plugin needs in the app's native files.
final class PluginRequirement {
  const PluginRequirement({
    required this.area,
    this.androidPermissions = const [],
    this.iosPlistKeys = const [],
    this.iosBackgroundModes = const [],
    this.androidServices = const [],
    this.androidRemoved = const [],
  });

  /// The plan that asked for it (CORE, PDF, LIBRARY, INFRA, …).
  final String area;

  /// Full permission names ([androidPermissionName]).
  final List<String> androidPermissions;
  final List<String> iosPlistKeys;
  final List<String> iosBackgroundModes;

  /// `<service>` declarations ([AndroidComponent.tag] = `service`).
  final List<AndroidComponent> androidServices;

  /// Entries the merge removes (`tools:node="remove"`).
  final List<AndroidComponent> androidRemoved;

  /// One cell of the `ws native-reqs` table.
  String get summary {
    final parts = [
      for (final permission in androidPermissions)
        permission.startsWith(_permissionPrefix)
            ? permission.substring(_permissionPrefix.length)
            : permission,
      for (final service in androidServices) 'service ${service.shortName}',
      for (final removed in androidRemoved)
        'remove ${removed.shortName}'.replaceFirst(
          'remove $_permissionPrefix',
          'remove ',
        ),
      ...iosPlistKeys,
      for (final mode in iosBackgroundModes) 'UIBackgroundModes $mode',
    ];
    return parts.isEmpty ? '-' : parts.join(', ');
  }
}

/// `tool/native_requirements.yaml` (4.3.2).
final class NativeRequirements {
  const NativeRequirements({
    required this.app,
    required this.flutterMinSdk,
    required this.flutterCompileSdk,
    required this.cocoapodsOnlyAllowed,
    required this.plugins,
    required this.pluginsWithoutRequirements,
    required this.appExtraAndroidPermissions,
    required this.appExtraIosPlist,
  });

  /// Reads the file at [path]. Throws [NativeReqsException].
  factory NativeRequirements.load(String path) {
    final file = File(path);
    if (!file.existsSync()) throw NativeReqsException('$path is missing');
    return NativeRequirements.parse(
      file.readAsStringSync(),
      source: p.basename(path),
    );
  }

  /// Parses the YAML [text]. Throws [NativeReqsException].
  factory NativeRequirements.parse(
    String text, {
    String source = 'native_requirements.yaml',
  }) {
    Never fail(String message) =>
        throw NativeReqsException('$source: $message');

    final Object? yaml;
    try {
      yaml = loadYaml(text);
    } on YamlException catch (e) {
      fail(e.message);
    }
    if (yaml is! YamlMap) fail('not a YAML map');

    YamlMap map(Object? value, String key) =>
        value is YamlMap ? value : fail('`$key` must be a map');
    String string(YamlMap from, String key, String where) {
      final value = from[key];
      if (value is String || value is num) return '$value';
      fail('`$where.$key` must be a string');
    }

    List<String> strings(Object? value, String where) {
      if (value == null) return const [];
      if (value is! YamlList || value.any((e) => e is! String)) {
        fail('`$where` must be a list of strings');
      }
      return List.unmodifiable(value.cast<String>());
    }

    String sdk(YamlMap from, String key) {
      final value = string(from, key, 'app');
      if (value == gradleFlutterDefault || RegExp(r'^\d+$').hasMatch(value)) {
        return value;
      }
      fail('`app.$key` must be a number or `$gradleFlutterDefault`');
    }

    int number(YamlMap from, String key, String where) {
      final value = from[key];
      return value is int ? value : fail('`$where.$key` must be an integer');
    }

    final app = map(yaml['app'], 'app');
    final allowBackup = app['android_allow_backup'];
    if (allowBackup is! bool) fail('`app.android_allow_backup` must be a bool');
    final iosTarget = string(app, 'ios_deployment_target', 'app');
    try {
      compareVersions(iosTarget, iosTarget);
    } on FormatException catch (e) {
      fail('`app.ios_deployment_target`: ${e.message}');
    }
    final defaults = map(yaml['flutter_defaults'], 'flutter_defaults');

    List<AndroidComponent> components(
      Object? value,
      String where, {
      String? tag,
    }) {
      if (value == null) return const [];
      if (value is! YamlList) fail('`$where` must be a list');
      return [
        for (final entry in value)
          () {
            if (entry is! YamlMap) fail('`$where` entries must be maps');
            final kind = tag ?? string(entry, 'tag', where);
            if (!const {
              'service',
              'receiver',
              'uses-permission',
            }.contains(kind)) {
              fail('`$where`: unknown tag `$kind`');
            }
            final attributes = <String, String>{};
            for (final MapEntry(:key, :value) in entry.entries) {
              if (key == 'name' || key == 'tag') continue;
              if (value is! String) fail('`$where.$key` must be a string');
              attributes['$key'] = value;
            }
            final name = string(entry, 'name', where);
            return AndroidComponent(
              tag: kind,
              name: kind == 'uses-permission'
                  ? androidPermissionName(name)
                  : name,
              attributes: Map.unmodifiable(attributes),
            );
          }(),
      ];
    }

    const pluginKeys = {
      'area',
      'android_permissions',
      'ios_plist_keys',
      'ios_background_modes',
      'android_services',
      'android_removed',
    };
    final plugins = <String, PluginRequirement>{};
    for (final MapEntry(:key, :value) in map(
      yaml['plugins'],
      'plugins',
    ).entries) {
      final where = 'plugins.$key';
      final entry = map(value, where);
      for (final field in entry.keys) {
        if (!pluginKeys.contains(field)) fail('`$where`: unknown key `$field`');
      }
      plugins['$key'] = PluginRequirement(
        area: string(entry, 'area', where),
        androidPermissions: [
          for (final name in strings(
            entry['android_permissions'],
            '$where.android_permissions',
          ))
            androidPermissionName(name),
        ],
        iosPlistKeys: strings(entry['ios_plist_keys'], '$where.ios_plist_keys'),
        iosBackgroundModes: strings(
          entry['ios_background_modes'],
          '$where.ios_background_modes',
        ),
        androidServices: components(
          entry['android_services'],
          '$where.android_services',
          tag: 'service',
        ),
        androidRemoved: components(
          entry['android_removed'],
          '$where.android_removed',
        ),
      );
    }
    final without = strings(
      yaml['plugins_without_requirements'],
      'plugins_without_requirements',
    ).toSet();
    final both = without.intersection(plugins.keys.toSet());
    if (both.isNotEmpty) {
      fail(
        'listed under both plugins and plugins_without_requirements: '
        '${(both.toList()..sort()).join(', ')}',
      );
    }

    final extra = yaml['app_extra'] == null
        ? YamlMap()
        : map(yaml['app_extra'], 'app_extra');
    final plist = extra['ios_plist'] == null
        ? YamlMap()
        : map(extra['ios_plist'], 'app_extra.ios_plist');
    return NativeRequirements(
      app: AppRequirements(
        iosDeploymentTarget: iosTarget,
        androidMinSdk: sdk(app, 'android_min_sdk'),
        androidCompileSdk: sdk(app, 'android_compile_sdk'),
        androidLabel: string(app, 'android_label', 'app'),
        androidAllowBackup: allowBackup,
        iosDisplayName: string(app, 'ios_display_name', 'app'),
      ),
      flutterMinSdk: number(defaults, 'min_sdk', 'flutter_defaults'),
      flutterCompileSdk: number(defaults, 'compile_sdk', 'flutter_defaults'),
      cocoapodsOnlyAllowed: strings(
        yaml['cocoapods_only_allowed'],
        'cocoapods_only_allowed',
      ).toSet(),
      plugins: Map.unmodifiable(plugins),
      pluginsWithoutRequirements: without,
      appExtraAndroidPermissions: [
        for (final name in strings(
          extra['android_permissions'],
          'app_extra.android_permissions',
        ))
          androidPermissionName(name),
      ],
      appExtraIosPlist: {
        for (final MapEntry(:key, :value) in plist.entries)
          '$key': value is bool || value is String
              ? value as Object
              : fail('`app_extra.ios_plist.$key` must be a bool or a string'),
      },
    );
  }

  final AppRequirements app;

  /// `flutter_defaults` — used when `FlutterExtension.kt` cannot be read.
  final int flutterMinSdk, flutterCompileSdk;

  /// iOS plugins allowed without `Package.swift` (V12: the two ML Kit ones).
  final Set<String> cocoapodsOnlyAllowed;
  final Map<String, PluginRequirement> plugins;
  final Set<String> pluginsWithoutRequirements;

  /// Full permission names of `app_extra.android_permissions`.
  final List<String> appExtraAndroidPermissions;
  final Map<String, Object> appExtraIosPlist;

  /// Every name the file lists ([plugins] and [pluginsWithoutRequirements]).
  Set<String> get listed => {...plugins.keys, ...pluginsWithoutRequirements};
}

// --- app/.flutter-plugins-dependencies --------------------------------------

/// One plugin of a platform list of `.flutter-plugins-dependencies`.
final class ResolvedPlugin {
  const ResolvedPlugin({
    required this.name,
    required this.path,
    required this.nativeBuild,
    required this.devDependency,
  });

  final String name;

  /// The package directory (absolute).
  final String path;

  /// `native_build`: false for Dart-only implementations (no podspec, no
  /// Gradle file — `path_provider_android` 2.3.1 uses jni).
  final bool nativeBuild;
  final bool devDependency;
}

/// `app/.flutter-plugins-dependencies` — the plugins Flutter resolved for
/// the app.
final class FlutterPluginsDependencies {
  const FlutterPluginsDependencies({
    required this.ios,
    required this.android,
    required this.dependencyGraph,
  });

  /// Parses the JSON [text]. Relative plugin paths resolve against
  /// [baseDirectory] (Flutter writes absolute ones). Throws
  /// [NativeReqsException].
  factory FlutterPluginsDependencies.parse(
    String text, {
    required String baseDirectory,
  }) {
    Never fail(String message) => throw NativeReqsException(
      '${NativeReqsPaths.pluginsDependencies}: $message',
    );
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      fail(e.message);
    }
    if (json is! Map<String, Object?>) fail('not a JSON object');
    final plugins = json['plugins'];
    if (plugins is! Map<String, Object?>) fail('`plugins` must be an object');

    List<ResolvedPlugin> platform(String name) {
      final list = plugins[name] ?? const <Object?>[];
      if (list is! List<Object?>) fail('`plugins.$name` must be a list');
      return [
        for (final entry in list)
          if (entry is Map<String, Object?> &&
              entry['name'] is String &&
              entry['path'] is String)
            ResolvedPlugin(
              name: entry['name']! as String,
              path: p.normalize(
                p.join(baseDirectory, entry['path']! as String),
              ),
              nativeBuild: entry['native_build'] != false,
              devDependency: entry['dev_dependency'] == true,
            )
          else
            fail('`plugins.$name` entries need `name` and `path`'),
      ];
    }

    final graph = json['dependencyGraph'];
    if (graph is! List<Object?>) fail('`dependencyGraph` must be a list');
    return FlutterPluginsDependencies(
      ios: platform('ios'),
      android: platform('android'),
      dependencyGraph: {
        for (final entry in graph)
          if (entry is Map<String, Object?> && entry['name'] is String)
            entry['name']! as String
          else
            fail('`dependencyGraph` entries need `name`'),
      },
    );
  }

  /// Reads the file at [path]. Throws [NativeReqsException] (missing →
  /// run `flutter pub get`).
  factory FlutterPluginsDependencies.load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw NativeReqsException(
        '$path is missing (run `flutter pub get` at the repository root)',
      );
    }
    return FlutterPluginsDependencies.parse(
      file.readAsStringSync(),
      baseDirectory: p.dirname(path),
    );
  }

  final List<ResolvedPlugin> ios, android;

  /// Names of `dependencyGraph`: every plugin the app resolves — app-facing,
  /// platform implementations, web-only, transitive and dev (NR6, contract
  /// 7.4.1 v2.2 C22-03).
  final Set<String> dependencyGraph;
}

// --- one plugin's native files ----------------------------------------------

/// `s.platform = :ios, 'x'` / `s.ios.deployment_target = 'x'` of a podspec —
/// the larger when both are there; null when neither. Full-line `#`
/// comments are ignored.
String? podspecIosMinimum(String text) {
  final code = text
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('#'))
      .join('\n');
  final values = [
    for (final pattern in [
      r'''\.platform\s*=\s*:ios\s*,\s*['"](\d+(?:\.\d+)*)['"]''',
      r'''\.ios\.deployment_target\s*=\s*['"](\d+(?:\.\d+)*)['"]''',
    ])
      for (final m in RegExp(pattern).allMatches(code)) m.group(1)!,
  ];
  if (values.isEmpty) return null;
  return values.reduce((a, b) => compareVersions(a, b) >= 0 ? a : b);
}

/// The iOS platform of a `Package.swift`: `.iOS("13.0")`, `.iOS(.v16)` →
/// `16.0`, `.iOS(.v16_4)` → `16.4`; null when none. `//` comments are
/// ignored.
String? swiftPackageIosMinimum(String text) {
  final code = text.replaceAll(RegExp(r'//[^\n]*'), '');
  final m = RegExp(r'\.iOS\(\s*(?:"(\d+(?:\.\d+)*)"|\.v(\d+)(?:_(\d+))?)\s*\)')
      .firstMatch(code);
  if (m == null) return null;
  return m.group(1) ?? '${m.group(2)}.${m.group(3) ?? '0'}';
}

/// `minSdkVersion` / `compileSdkVersion` of Flutter's `FlutterExtension.kt`
/// (24 / 36 in Flutter 3.47.9); null when either is missing.
({int minSdk, int compileSdk})? flutterGradleDefaults(String kotlin) {
  int? value(String name) {
    final m = RegExp('val\\s+$name\\s*:\\s*Int\\s*=\\s*(\\d+)')
        .firstMatch(kotlin);
    return m == null ? null : int.parse(m.group(1)!);
  }

  final min = value('minSdkVersion'), compile = value('compileSdkVersion');
  return min == null || compile == null
      ? null
      : (minSdk: min, compileSdk: compile);
}

/// What `ws native-reqs` reads from one plugin directory (6.3 table).
final class PluginNativeInfo {
  const PluginNativeInfo({
    this.hasPodspec = false,
    this.podIos,
    this.hasSwiftPackage = false,
    this.swiftPackageIos,
    this.hasGradle = false,
    this.androidMinSdk,
    this.androidCompileSdk,
  });

  /// Reads `ios/` or `darwin/` (`*.podspec`, `<name>/Package.swift`) and
  /// `android/build.gradle(.kts)` under [directory]. Throws
  /// [NativeReqsException] when [directory] does not exist.
  factory PluginNativeInfo.read(String name, String directory) {
    if (!Directory(directory).existsSync()) {
      throw NativeReqsException(
        'plugin $name: $directory is missing (run `flutter pub get`)',
      );
    }
    String? podspec, swiftPackage, gradle;
    for (final apple in const ['ios', 'darwin']) {
      final dir = Directory(p.join(directory, apple));
      if (!dir.existsSync()) continue;
      final specs =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.podspec'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (specs.isNotEmpty) podspec ??= specs.first.readAsStringSync();
      final package = File(p.join(dir.path, name, 'Package.swift'));
      if (package.existsSync()) swiftPackage ??= package.readAsStringSync();
    }
    for (final file in const ['build.gradle.kts', 'build.gradle']) {
      final f = File(p.join(directory, 'android', file));
      if (f.existsSync()) {
        gradle = f.readAsStringSync();
        break;
      }
    }
    return PluginNativeInfo(
      hasPodspec: podspec != null,
      podIos: podspec == null ? null : podspecIosMinimum(podspec),
      hasSwiftPackage: swiftPackage != null,
      swiftPackageIos: swiftPackage == null
          ? null
          : swiftPackageIosMinimum(swiftPackage),
      hasGradle: gradle != null,
      androidMinSdk: gradle == null ? null : gradleSdkValue(gradle, 'minSdk'),
      androidCompileSdk: gradle == null
          ? null
          : gradleSdkValue(gradle, 'compileSdk'),
    );
  }

  final bool hasPodspec;
  final String? podIos;
  final bool hasSwiftPackage;
  final String? swiftPackageIos;
  final bool hasGradle;

  /// As [gradleSdkValue] returns them.
  final String? androidMinSdk, androidCompileSdk;

  /// The higher of [podIos] and [swiftPackageIos] (null when neither).
  String? get iosMinimum {
    final values = [?podIos, ?swiftPackageIos];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => compareVersions(a, b) >= 0 ? a : b);
  }
}

// --- NR7: requirements against the app's files ------------------------------

/// Every listed requirement — of the plugins, `app:` and `app_extra:` —
/// that [config] does not meet, one line each (NR7; empty = all met).
/// `tool/test/native_config_test.dart` runs it on the committed files (the
/// CI gate); `ws native-reqs` prints the same lines. Lines that name the same
/// setting as [appNativeConfigProblems] use its wording.
List<String> nativeRequirementProblems(
  NativeRequirements requirements,
  NativeConfig config,
) {
  final problems = <String>{};
  final manifest = config.manifest;
  final plist = config.infoPlist;

  void permission(String name) {
    if (!manifest.permissions.contains(name)) {
      problems.add('AndroidManifest: missing <uses-permission $name>');
    }
  }

  void backgroundMode(String mode) {
    final modes = plist['UIBackgroundModes'];
    if (modes is! List || !modes.contains(mode)) {
      problems.add('Info.plist: UIBackgroundModes lacks $mode');
    }
  }

  // --- app: ---
  final app = requirements.app;
  for (final value in {
    ...config.deploymentTargets,
    if (config.deploymentTargets.isEmpty) '(none)',
  }) {
    if (value != app.iosDeploymentTarget) {
      problems.add(
        'project.pbxproj: IPHONEOS_DEPLOYMENT_TARGET = $value, expected '
        '${app.iosDeploymentTarget}',
      );
    }
  }
  if (config.podfile.platformIos != app.iosDeploymentTarget) {
    problems.add(
      "Podfile: platform :ios is ${config.podfile.platformIos ?? '(none)'}, "
      "expected '${app.iosDeploymentTarget}'",
    );
  }
  if (config.podfile.iosVersion != app.iosDeploymentTarget) {
    problems.add(
      "Podfile: \$iOSVersion is ${config.podfile.iosVersion ?? '(none)'}, "
      "expected '${app.iosDeploymentTarget}'",
    );
  }
  for (final (key, actual, expected) in [
    ('minSdk', config.androidGradle.minSdk, app.androidMinSdk),
    ('compileSdk', config.androidGradle.compileSdk, app.androidCompileSdk),
  ]) {
    if (actual != expected) {
      String show(String? v) =>
          v == gradleFlutterDefault ? 'flutter.${key}Version' : v ?? '(none)';
      problems.add(
        'build.gradle.kts: $key is ${show(actual)}, expected ${show(expected)}',
      );
    }
  }
  final label = manifest.application['android:label'];
  if (label != app.androidLabel) {
    problems.add(
      'AndroidManifest: android:label is ${label ?? '(none)'}, expected '
      '${app.androidLabel}',
    );
  }
  if (manifest.application['android:allowBackup'] !=
      '${app.androidAllowBackup}') {
    problems.add(
      'AndroidManifest: android:allowBackup must be '
      '"${app.androidAllowBackup}" (D20)',
    );
  }
  if (plist['CFBundleDisplayName'] != app.iosDisplayName) {
    problems.add(
      'Info.plist: CFBundleDisplayName is '
      '${plist['CFBundleDisplayName'] ?? '(none)'}, expected '
      '"${app.iosDisplayName}"',
    );
  }

  // --- app_extra: ---
  requirements.appExtraAndroidPermissions.forEach(permission);
  for (final MapEntry(:key, :value) in requirements.appExtraIosPlist.entries) {
    if (plist[key] != value) {
      problems.add(
        'Info.plist: $key is ${plist[key] ?? '(none)'}, expected '
        '${value is String ? '"$value"' : value}',
      );
    }
  }

  // --- plugins: ---
  final names = requirements.plugins.keys.toList()..sort();
  for (final name in names) {
    final requirement = requirements.plugins[name]!;
    requirement.androidPermissions.forEach(permission);
    for (final service in requirement.androidServices) {
      final declared = manifest.services[service.name];
      if (declared == null) {
        problems.add('AndroidManifest: missing <service ${service.name}>');
        continue;
      }
      for (final MapEntry(:key, :value) in service.attributes.entries) {
        final actual = declared['android:$key'];
        if (actual != value) {
          problems.add(
            'AndroidManifest: ${service.shortName} android:$key is '
            '${actual ?? '(none)'}, expected $value',
          );
        }
      }
    }
    for (final removed in requirement.androidRemoved) {
      final isRemoved = switch (removed.tag) {
        'uses-permission' => manifest.removedPermissions.contains(removed.name),
        'receiver' =>
          manifest.receivers[removed.name]?['tools:node'] == 'remove',
        _ => manifest.services[removed.name]?['tools:node'] == 'remove',
      };
      if (!isRemoved) {
        problems.add(
          'AndroidManifest: ${removed.name} is not removed '
          '(tools:node="remove")',
        );
      }
    }
    for (final key in requirement.iosPlistKeys) {
      final value = plist[key];
      if (value is! String || value.trim().isEmpty) {
        problems.add('Info.plist: $key is missing or empty (needed by $name)');
      }
    }
    requirement.iosBackgroundModes.forEach(backgroundMode);
  }
  return problems.toList();
}

// --- the whole check --------------------------------------------------------

/// One finding of [checkNativeRequirements].
final class NativeReqsFinding {
  const NativeReqsFinding(this.rule, this.message, {this.warning = false});

  /// `NR1` … `NR7`.
  final String rule;
  final String message;

  /// NR4 (and stale names in the requirements file): shown, exit code 0.
  final bool warning;

  @override
  String toString() => '$rule${warning ? ' warning' : ''}: $message';
}

/// One row of the `ws native-reqs` table.
final class NativeReqsRow {
  const NativeReqsRow({
    required this.name,
    required this.info,
    required this.requirement,
  });

  final String name;

  /// Null for a Dart-only implementation (`native_build: false`).
  final PluginNativeInfo? info;

  /// Null when the plugin is not under `plugins` of the requirements file.
  final PluginRequirement? requirement;
}

/// The result of [checkNativeRequirements].
final class NativeReqsReport {
  const NativeReqsReport({
    required this.rows,
    required this.findings,
    required this.appIos,
    required this.appMinSdk,
    required this.appMinSdkNote,
    required this.appCompileSdk,
    required this.appCompileSdkNote,
    required this.cocoapodsOnly,
  });

  final List<NativeReqsRow> rows;
  final List<NativeReqsFinding> findings;

  /// The app's iOS deployment target (lowest value of the Xcode project).
  final String appIos;

  /// Resolved Android SDK levels of the app.
  final int appMinSdk, appCompileSdk;

  /// Where each level came from: ` (flutter — FlutterExtension.kt)`,
  /// ` (flutter — flutter_defaults)` or empty for a number in
  /// `build.gradle.kts`.
  final String appMinSdkNote, appCompileSdkNote;

  /// iOS plugins without `Package.swift` (sorted).
  final List<String> cocoapodsOnly;

  Iterable<NativeReqsFinding> get violations =>
      findings.where((f) => !f.warning);
  Iterable<NativeReqsFinding> get warnings => findings.where((f) => f.warning);

  /// The table, the app line, the findings and a summary line.
  String format() {
    final buffer = StringBuffer();
    final header = [
      'plugin',
      'ios(pod)',
      'ios(spm)',
      'minSdk',
      'compileSdk',
      'requirements',
    ];
    String sdk(String? v) => v ?? '-';
    final table = [
      header,
      for (final row in rows)
        if (row.info case final info?)
          [
            row.name,
            info.hasPodspec ? info.podIos ?? '?' : '-',
            info.hasSwiftPackage ? info.swiftPackageIos ?? '?' : 'no',
            info.hasGradle ? sdk(info.androidMinSdk) : '-',
            info.hasGradle ? sdk(info.androidCompileSdk) : '-',
            row.requirement?.summary ?? '-',
          ]
        else
          [
            row.name,
            '-',
            '-',
            '-',
            '-',
            '(Dart only) ${row.requirement?.summary ?? '-'}',
          ],
    ];
    final widths = [
      for (var c = 0; c < header.length - 1; c++)
        table.fold(0, (w, r) => r[c].length > w ? r[c].length : w),
    ];
    for (final r in table) {
      buffer.writeln(
        [
          for (var c = 0; c < widths.length; c++) r[c].padRight(widths[c]),
          r.last,
        ].join(' ').trimRight(),
      );
    }
    buffer.writeln(
      'app: ios $appIos · minSdk $appMinSdk$appMinSdkNote · compileSdk '
      '$appCompileSdk$appCompileSdkNote · CocoaPods-only: '
      '${cocoapodsOnly.isEmpty ? '(none)' : cocoapodsOnly.join(', ')}',
    );
    for (final finding in findings) {
      buffer.writeln(finding);
    }
    buffer.writeln(
      'ws native-reqs: ${rows.length} plugin(s), ${violations.length} '
      'violation(s), ${warnings.length} warning(s)',
    );
    return buffer.toString();
  }
}

/// Runs NR1–NR7 (6.3). [pluginPackages] is `plugin_packages` of
/// `tool/workspace_rules.yaml`; [flutterDefaults] comes from
/// `FlutterExtension.kt` (null → `flutter_defaults` of [requirements]);
/// [appProblems] are added to NR7 (the CLI passes
/// [appNativeConfigProblems]); [readPlugin] reads a plugin directory
/// (default [PluginNativeInfo.read]).
NativeReqsReport checkNativeRequirements({
  required NativeRequirements requirements,
  required FlutterPluginsDependencies dependencies,
  required List<String> pluginPackages,
  required NativeConfig config,
  ({int minSdk, int compileSdk})? flutterDefaults,
  Iterable<String> appProblems = const [],
  PluginNativeInfo Function(ResolvedPlugin plugin)? readPlugin,
}) {
  final read = readPlugin ?? (r) => PluginNativeInfo.read(r.name, r.path);
  final findings = <NativeReqsFinding>[];

  // The plugins of the two native platforms, by name (a plugin builds native
  // code when either platform entry says so).
  final native = <String, ResolvedPlugin>{};
  for (final plugin in [...dependencies.ios, ...dependencies.android]) {
    final known = native[plugin.name];
    if (known == null || (!known.nativeBuild && plugin.nativeBuild)) {
      native[plugin.name] = plugin;
    }
  }
  final iosNames = {for (final plugin in dependencies.ios) plugin.name};
  final androidNames = {for (final plugin in dependencies.android) plugin.name};
  final infos = <String, PluginNativeInfo?>{
    for (final MapEntry(:key, :value) in native.entries)
      key: value.nativeBuild ? read(value) : null,
  };
  final names = native.keys.toList()..sort();

  // App values.
  final targets = [
    ...config.deploymentTargets.where(
      (t) => RegExp(r'^\d+(\.\d+)*$').hasMatch(t),
    ),
  ]..sort(compareVersions);
  final appIos = targets.isEmpty
      ? requirements.app.iosDeploymentTarget
      : targets.first;
  final defaults =
      flutterDefaults ??
      (
        minSdk: requirements.flutterMinSdk,
        compileSdk: requirements.flutterCompileSdk,
      );
  final flutterSource = flutterDefaults == null
      ? ' (flutter — flutter_defaults)'
      : ' (flutter — FlutterExtension.kt)';
  final gradle = config.androidGradle;
  int appSdk(String? value, int flutter) =>
      int.tryParse(value ?? '') ?? flutter;
  String note(String? value) =>
      value == gradleFlutterDefault ? flutterSource : '';
  final appMinSdk = appSdk(gradle.minSdk, defaults.minSdk);
  final appCompileSdk = appSdk(gradle.compileSdk, defaults.compileSdk);

  // NR1
  final listed = requirements.listed;
  for (final name in names) {
    if (!listed.contains(name)) {
      findings.add(
        NativeReqsFinding(
          'NR1',
          '$name is an iOS / Android plugin of the app but '
              '${NativeReqsPaths.requirements} does not list it (plugins or '
              'plugins_without_requirements)',
        ),
      );
    }
  }
  for (final name in listed.toList()..sort()) {
    if (!native.containsKey(name)) {
      findings.add(
        NativeReqsFinding(
          'NR1',
          '${NativeReqsPaths.requirements} lists $name, which the app does '
              'not resolve for iOS or Android',
          warning: true,
        ),
      );
    }
  }

  for (final name in names) {
    final info = infos[name];
    if (info == null) continue;
    // NR2
    final ios = info.iosMinimum;
    if (iosNames.contains(name) &&
        ios != null &&
        compareVersions(ios, appIos) > 0) {
      findings.add(
        NativeReqsFinding(
          'NR2',
          '$name needs iOS $ios, the app targets $appIos',
        ),
      );
    }
    // NR3 / NR4
    if (!androidNames.contains(name)) continue;
    for (final (rule, value, app, what) in [
      ('NR3', info.androidMinSdk, appMinSdk, 'minSdk'),
      ('NR4', info.androidCompileSdk, appCompileSdk, 'compileSdk'),
    ]) {
      final level = int.tryParse(value ?? '');
      if (level != null && level > app) {
        findings.add(
          NativeReqsFinding(
            rule,
            '$name needs $what $level, the app has $app',
            warning: rule == 'NR4',
          ),
        );
      }
    }
  }

  // NR5
  final cocoapodsOnly = [
    for (final name in names)
      if (infos[name]
          case PluginNativeInfo(hasPodspec: true, hasSwiftPackage: false)
          when iosNames.contains(name))
        name,
  ];
  final allowed = requirements.cocoapodsOnlyAllowed;
  for (final name in cocoapodsOnly) {
    if (!allowed.contains(name)) {
      findings.add(
        NativeReqsFinding(
          'NR5',
          '$name has no Package.swift (CocoaPods only) and is not in '
              'cocoapods_only_allowed',
        ),
      );
    }
  }
  for (final name in allowed.toList()..sort()) {
    if (!cocoapodsOnly.contains(name)) {
      findings.add(
        NativeReqsFinding(
          'NR5',
          'cocoapods_only_allowed lists $name, which is not a CocoaPods-only '
              'iOS plugin of the app',
        ),
      );
    }
  }

  // NR6
  final packages = pluginPackages.toSet();
  final graph = dependencies.dependencyGraph;
  final missing = graph.difference(packages).toList()..sort();
  final extra = packages.difference(graph).toList()..sort();
  if (missing.isNotEmpty) {
    findings.add(
      NativeReqsFinding(
        'NR6',
        'plugin_packages (tool/workspace_rules.yaml) lacks '
            '${missing.join(', ')} (in dependencyGraph)',
      ),
    );
  }
  if (extra.isNotEmpty) {
    findings.add(
      NativeReqsFinding(
        'NR6',
        'plugin_packages (tool/workspace_rules.yaml) has '
            '${extra.join(', ')}, not in dependencyGraph',
      ),
    );
  }

  // NR7
  for (final problem in {
    ...nativeRequirementProblems(requirements, config),
    ...appProblems,
  }) {
    findings.add(NativeReqsFinding('NR7', problem));
  }

  return NativeReqsReport(
    rows: [
      for (final name in names)
        NativeReqsRow(
          name: name,
          info: infos[name],
          requirement: requirements.plugins[name],
        ),
    ],
    findings: findings,
    appIos: appIos,
    appMinSdk: appMinSdk,
    appMinSdkNote: note(gradle.minSdk),
    appCompileSdk: appCompileSdk,
    appCompileSdkNote: note(gradle.compileSdk),
    cocoapodsOnly: cocoapodsOnly,
  );
}
