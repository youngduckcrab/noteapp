// Static checks of the committed native configuration (V12 — docs/plans/
// m5-7/01-infra.md 6.10.1, 6.11.1–6.11.4, 9.1 and appendix B; contract
// 00-overview 7.4.3 v2.1). The container has no Android SDK or Xcode, so the
// manifest, Info.plist, Xcode project, Podfile and xcconfig files are read as
// text; the real builds are android.yml / ios-compile.yml (CI).
//
// J0 part: the parsers, the committed files and every rule of
// appNativeConfigProblems (each one broken on purpose once). J1 part:
// tool/native_requirements.yaml fully met (the NR7 check of `ws
// native-reqs`, tool/test/native_reqs_test.dart) and agreeing with
// AppNativeExpectations. J2 part: the build.gradle.kts release signing
// branch (the committed file and each rule broken once). J4 part: the app
// shell's two native storage paths (6.9 — tool/src/app_shell_storage.dart on
// the committed app/lib files, each rule broken once).

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/app_shell_storage.dart';
import '../src/native_config.dart';
import '../src/native_reqs.dart';
import 'support/fixture_workspace.dart';

String _read(String path) => File(p.join(repoRoot, path)).readAsStringSync();

/// [NativeConfig] from the committed files with one file's text changed.
NativeConfig _withEdit(String path, String Function(String text) edit) {
  String text(String file) => file == path ? edit(_read(file)) : _read(file);
  return NativeConfig(
    manifest: AndroidManifestInfo.parse(
      text(NativeConfigPaths.androidManifest),
    ),
    androidGradle: AndroidGradleInfo.parse(
      text(NativeConfigPaths.androidGradle),
    ),
    infoPlist: parsePlist(text(NativeConfigPaths.infoPlist)),
    deploymentTargets: pbxDeploymentTargets(text(NativeConfigPaths.pbxproj)),
    podfile: PodfileInfo.parse(text(NativeConfigPaths.podfile)),
    debugXcconfig: xcconfigIncludes(text(NativeConfigPaths.debugXcconfig)),
    releaseXcconfig: xcconfigIncludes(text(NativeConfigPaths.releaseXcconfig)),
  );
}

/// Replaces [from] (which must occur) with [to].
String Function(String) _replace(String from, String to) => (text) {
  expect(text, contains(from), reason: 'fixture edit: $from');
  return text.replaceAll(from, to);
};

void main() {
  group('parsers', () {
    test('AndroidManifestInfo: permissions, removals, application, services, '
        'receivers — comments and attribute order do not matter', () {
      final info = AndroidManifestInfo.parse('''
<manifest xmlns:tools="http://schemas.android.com/tools"
    xmlns:android="http://schemas.android.com/apk/res/android">
  <!-- <uses-permission android:name="android.permission.CAMERA"/> -->
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission tools:node="remove" android:name="android.permission.WAKE_LOCK"/>
  <application android:allowBackup="false" android:label="x">
    <service android:exported="false" android:name="a.B"/>
    <receiver tools:node="remove" android:name="a.R"/>
    <activity android:name=".Main"/>
  </application>
</manifest>''');
      expect(info.permissions, {'android.permission.INTERNET'});
      expect(info.removedPermissions, {'android.permission.WAKE_LOCK'});
      expect(info.application, {
        'android:allowBackup': 'false',
        'android:label': 'x',
      });
      expect(info.services, {
        'a.B': {'android:exported': 'false', 'android:name': 'a.B'},
      });
      expect(info.receivers['a.R']!['tools:node'], 'remove');
      expect(info.declaresToolsNamespace, isTrue);
    });

    test('AndroidManifestInfo: bad input throws NativeConfigException', () {
      for (final text in [
        '<manifest',
        '<other/>',
        '<manifest><application/><application/></manifest>',
        '<manifest/>',
      ]) {
        expect(
          () => AndroidManifestInfo.parse(text),
          throwsA(isA<NativeConfigException>()),
          reason: text,
        );
      }
      expect(
        AndroidManifestInfo.parse('<manifest><application/></manifest>')
            .declaresToolsNamespace,
        isFalse,
      );
    });

    test('parsePlist: nested values', () {
      expect(
        parsePlist('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>s</key><string>필기노트</string>
  <key>t</key><true/>
  <key>f</key><false/>
  <key>i</key><integer>42</integer>
  <key>r</key><real>1.5</real>
  <key>a</key><array><string>audio</string><string>fetch</string></array>
  <key>d</key><dict><key>k</key><string>v</string></dict>
  <key>e</key><string></string>
</dict>
</plist>'''),
        {
          's': '필기노트',
          't': true,
          'f': false,
          'i': 42,
          'r': 1.5,
          'a': ['audio', 'fetch'],
          'd': {'k': 'v'},
          'e': '',
        },
      );
      for (final bad in [
        '<plist><array/></plist>',
        '<plist><dict><key>a</key></dict></plist>',
        '<plist><dict><string>a</string><string>b</string></dict></plist>',
        '<plist><dict><key>a</key><weird/></dict></plist>',
        '<dict/>',
      ]) {
        expect(
          () => parsePlist(bad),
          throwsA(isA<NativeConfigException>()),
          reason: bad,
        );
      }
    });

    test('pbxDeploymentTargets: every value in order', () {
      expect(
        pbxDeploymentTargets('''
				IPHONEOS_DEPLOYMENT_TARGET = 15.5;
				SDKROOT = iphoneos;
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				IPHONEOS_DEPLOYMENT_TARGET = "16.0";
'''),
        ['15.5', '15.0', '"16.0"'],
      );
      expect(pbxDeploymentTargets(''), isEmpty);
    });

    test('PodfileInfo: commented-out lines do not count', () {
      final commented = PodfileInfo.parse('''
# platform :ios, '15.5'
# \$iOSVersion = '15.5'
target 'Runner' do
end
''');
      expect(commented.platformIos, isNull);
      expect(commented.iosVersion, isNull);
      expect(commented.excludesArmv7, isFalse);
      expect(commented.usesFrameworks, isFalse);

      final set = PodfileInfo.parse('''
platform :ios, '16.0'
\$iOSVersion = '16.0'
  use_frameworks!
    config.build_settings["EXCLUDED_ARCHS[sdk=*]"] = "armv7"
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = \$iOSVersion
    flutter_additional_ios_build_settings(target)
      if Gem::Version.new(\$iOSVersion) > Gem::Version.new(config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'])
''');
      expect(set.platformIos, '16.0');
      expect(set.iosVersion, '16.0');
      expect(set.excludesArmv7, isTrue);
      expect(set.setsPodsDeploymentTarget, isTrue);
      expect(set.raisesTargetDeploymentTargets, isTrue);
      expect(set.callsFlutterAdditionalSettings, isTrue);
      expect(set.usesFrameworks, isTrue);
    });

    test('xcconfigIncludes: #include and #include? in order', () {
      expect(
        xcconfigIncludes('''
#include? "Pods/x.xcconfig"
// #include "commented.xcconfig"
#include "Generated.xcconfig"
FOO = bar
'''),
        [
          (path: 'Pods/x.xcconfig', optional: true),
          (path: 'Generated.xcconfig', optional: false),
        ],
      );
    });

    test('NativeConfig.load: a missing file throws', () {
      final dir = Directory.systemTemp.createTempSync('native_config_');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(
        () => NativeConfig.load(dir.path),
        throwsA(
          isA<NativeConfigException>().having(
            (e) => e.message,
            'message',
            contains(NativeConfigPaths.androidManifest),
          ),
        ),
      );
    });
  });

  group('AndroidGradleInfo (J1 SDK levels, J2 signing branch)', () {
    test('SDK levels as gradleSdkValue reads them', () {
      final info = AndroidGradleInfo.parse(
        'minSdk = 26 // was flutter.minSdkVersion\n'
        'compileSdk = flutter.compileSdkVersion',
      );
      expect((info.minSdk, info.compileSdk), ('26', 'flutter'));
      expect(info.keyPropertiesFile, isNull);
      expect(info.createsReleaseSigningOnlyWithKeyProperties, isFalse);
      expect(info.releaseUsesReleaseKeyElseDebug, isFalse);
    });

    test('the signing branch under any variable name, comments ignored', () {
      final info = AndroidGradleInfo.parse('''
val props = rootProject.file("signing/key.properties")
val loaded = Properties()
android {
    signingConfigs {
        if (props.exists()) {
            create("release") {
                storeFile = file(loaded.getProperty("storeFile"))
                keyAlias = loaded.getProperty("keyAlias")
                // keyPassword = loaded.getProperty("keyPassword")
                storePassword = loaded.getProperty("keyAlias")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (props.exists())
                signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}
''');
      expect(info.keyPropertiesFile, 'signing/key.properties');
      expect(info.createsReleaseSigningOnlyWithKeyProperties, isTrue);
      // storePassword reads another entry; keyPassword is commented out.
      expect(info.signingProperties, {'storeFile', 'keyAlias'});
      expect(info.releaseUsesReleaseKeyElseDebug, isTrue);
    });
  });

  group('the committed files (J0)', () {
    late NativeConfig config;
    setUpAll(() => config = NativeConfig.load(repoRoot));

    test('no problem at all', () {
      expect(appNativeConfigProblems(config), isEmpty);
    });

    test('Android manifest (6.10.1): permissions, boot removal, label, '
        'allowBackup, the recording service', () {
      final m = config.manifest;
      expect(m.declaresToolsNamespace, isTrue);
      expect(m.permissions, {
        'android.permission.INTERNET',
        'android.permission.RECORD_AUDIO',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_MICROPHONE',
        'android.permission.POST_NOTIFICATIONS',
      });
      expect(m.removedPermissions, {
        'android.permission.RECEIVE_BOOT_COMPLETED',
      });
      expect(m.application['android:label'], '필기노트');
      expect(m.application['android:allowBackup'], 'false');
      expect(m.application['android:name'], r'${applicationName}');
      expect(m.services[AppNativeExpectations.foregroundService], {
        'android:name': AppNativeExpectations.foregroundService,
        'android:foregroundServiceType': 'microphone',
        'android:exported': 'false',
        'android:stopWithTask': 'true',
      });
      expect(m.receivers.keys, [AppNativeExpectations.rebootReceiver]);
      expect(
        m.receivers[AppNativeExpectations.rebootReceiver]!['tools:node'],
        'remove',
      );
      // The service / receiver names are the ones of the plugin's manifest
      // and README (flutter_foreground_task 11.0.3).
      expect(
        AppNativeExpectations.foregroundService,
        startsWith('com.pravera.flutter_foreground_task.service.'),
      );
    });

    test('Info.plist (6.11.4): the strings exactly, audio background, no '
        'export compliance question', () {
      final plist = config.infoPlist;
      expect(plist['CFBundleDisplayName'], '필기노트');
      expect(plist['NSMicrophoneUsageDescription'], '노트에 녹음을 붙이려면 마이크가 필요해요.');
      expect(
        plist['NSPhotoLibraryUsageDescription'],
        '사진을 노트에 넣으려면 사진 보관함에 접근해야 해요.',
      );
      expect(plist['NSCameraUsageDescription'], '사진을 찍어 노트에 넣으려면 카메라가 필요해요.');
      expect(plist['UIBackgroundModes'], ['audio']);
      expect(plist['ITSAppUsesNonExemptEncryption'], isFalse);
      // 1차 keys stay (UIScene, orientations).
      expect(plist['UIApplicationSceneManifest'], isA<Map<String, Object>>());
      expect(plist['UISupportedInterfaceOrientations~ipad'], hasLength(4));
    });

    test('Xcode project (6.11.1): IPHONEOS_DEPLOYMENT_TARGET = 16.0 exactly '
        '3 times, no 15.0', () {
      expect(config.deploymentTargets, ['16.0', '16.0', '16.0']);
      expect(
        _read(NativeConfigPaths.pbxproj),
        isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0;')),
      );
    });

    test('Podfile (6.11.2): the template plus the ML Kit lines', () {
      final podfile = config.podfile;
      expect(podfile.platformIos, '16.0');
      expect(podfile.iosVersion, '16.0');
      expect(podfile.excludesArmv7, isTrue);
      expect(podfile.setsPodsDeploymentTarget, isTrue);
      expect(podfile.raisesTargetDeploymentTargets, isTrue);
      expect(podfile.callsFlutterAdditionalSettings, isTrue);
      expect(podfile.usesFrameworks, isTrue);
      // The Flutter 3.47.9 template lines are kept (risk 2 in 11).
      final text = _read(NativeConfigPaths.podfile);
      for (final line in [
        "ENV['COCOAPODS_DISABLE_STATS'] = 'true'",
        "require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)",
        'flutter_ios_podfile_setup',
        'flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))',
        "target 'RunnerTests' do",
      ]) {
        expect(text, contains(line));
      }
    });

    test('Podfile: the template file of this Flutter still has the lines the '
        'committed Podfile copies', () {
      final flutterRoot = _flutterRoot();
      if (flutterRoot == null) {
        markTestSkipped('flutter not on PATH');
        return;
      }
      final template = File(
        p.join(
          flutterRoot,
          'packages',
          'flutter_tools',
          'templates',
          'cocoapods',
          'Podfile-ios',
        ),
      ).readAsStringSync();
      final committed = _read(NativeConfigPaths.podfile);
      for (final line in template.split('\n')) {
        final code = line.trim();
        // Skip comments, blank lines and the lines 6.11.2 changes.
        if (code.isEmpty || code.startsWith('#')) continue;
        expect(committed, contains(line), reason: 'template line: $line');
      }
    });

    test('build.gradle.kts (6.10.2, J2): the fixed key when key.properties '
        'exists, else the debug key', () {
      final gradle = config.androidGradle;
      expect(gradle.keyPropertiesFile, 'key.properties');
      expect(gradle.createsReleaseSigningOnlyWithKeyProperties, isTrue);
      expect(gradle.signingProperties, AppNativeExpectations.signingProperties);
      expect(gradle.releaseUsesReleaseKeyElseDebug, isTrue);
      // `rootProject` is app/android (its settings.gradle.kts), where
      // android.yml writes the file — and git never takes it.
      expect(
        File(p.join(repoRoot, 'app/android/settings.gradle.kts')).existsSync(),
        isTrue,
      );
      final ignored = Process.runSync('git', [
        'check-ignore',
        '-q',
        'app/android/key.properties',
      ], workingDirectory: repoRoot);
      expect(ignored.exitCode, 0, reason: 'key.properties must be ignored');
    });

    test('xcconfig (6.11.3): #include? of the pods file first, then '
        'Generated.xcconfig', () {
      for (final (mode, includes) in [
        ('debug', config.debugXcconfig),
        ('release', config.releaseXcconfig),
      ]) {
        expect(includes, [
          (
            path:
                'Pods/Target Support Files/Pods-Runner/Pods-Runner.$mode.xcconfig',
            optional: true,
          ),
          (path: 'Generated.xcconfig', optional: false),
        ], reason: mode);
      }
    });
  });

  group('every rule catches its own break', () {
    const manifest = NativeConfigPaths.androidManifest;
    const plist = NativeConfigPaths.infoPlist;
    const podfile = NativeConfigPaths.podfile;
    // name → (file, edit, the problems it causes — substrings, one each).
    final cases = <String, (String, String Function(String), Object)>{
      'xmlns:tools missing': (
        manifest,
        _replace('\n    xmlns:tools="http://schemas.android.com/tools"', ''),
        'lacks xmlns:tools',
      ),
      'a permission missing': (
        manifest,
        _replace(
          '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
          '',
        ),
        'missing <uses-permission android.permission.POST_NOTIFICATIONS>',
      ),
      'boot permission not removed': (
        manifest,
        _replace(
          'tools:node="remove"/>\n    <!-- allowBackup',
          '/>\n    <!-- allowBackup',
        ),
        // Without the removal it is a declared permission too.
        [
          'RECEIVE_BOOT_COMPLETED is not removed',
          'RECEIVE_BOOT_COMPLETED is also declared',
        ],
      ),
      'label': (
        manifest,
        _replace('android:label="필기노트"', 'android:label="noteapp"'),
        'android:label is noteapp',
      ),
      'allowBackup': (
        manifest,
        _replace('android:allowBackup="false"', 'android:allowBackup="true"'),
        'allowBackup must be "false"',
      ),
      'service type': (
        manifest,
        _replace(
          'android:foregroundServiceType="microphone"',
          'android:foregroundServiceType="dataSync"',
        ),
        'foregroundServiceType is dataSync',
      ),
      'service stopWithTask': (
        manifest,
        _replace('android:stopWithTask="true"', ''),
        'stopWithTask is (none)',
      ),
      'service missing': (
        manifest,
        _replace(
          'com.pravera.flutter_foreground_task.service.ForegroundService',
          'com.example.Other',
        ),
        'missing <service com.pravera',
      ),
      'reboot receiver kept': (
        manifest,
        _replace(
          'android:name="com.pravera.flutter_foreground_task.service.RebootReceiver"\n            tools:node="remove"',
          'android:name="com.pravera.flutter_foreground_task.service.RebootReceiver"',
        ),
        'RebootReceiver is not removed',
      ),
      'microphone text': (
        plist,
        _replace('마이크가 필요해요.', '마이크가 필요합니다.'),
        'NSMicrophoneUsageDescription is 노트에 녹음을 붙이려면 마이크가 필요합니다.',
      ),
      'photo text (PDF draft wording)': (
        plist,
        _replace('사진 보관함에 접근해야 해요.', '사진 보관함을 열어야 해요.'),
        'NSPhotoLibraryUsageDescription',
      ),
      'camera key missing': (
        plist,
        _replace('<key>NSCameraUsageDescription</key>', '<key>NSCameraX</key>'),
        'NSCameraUsageDescription is (none)',
      ),
      'background audio missing': (
        plist,
        _replace('<string>audio</string>', '<string>fetch</string>'),
        'UIBackgroundModes lacks audio',
      ),
      'encryption key true': (
        plist,
        _replace(
          '<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>',
          '<key>ITSAppUsesNonExemptEncryption</key>\n\t<true/>',
        ),
        'ITSAppUsesNonExemptEncryption is true',
      ),
      'one deployment target left at 15.0': (
        NativeConfigPaths.pbxproj,
        (text) => text.replaceFirst(
          'IPHONEOS_DEPLOYMENT_TARGET = 16.0;',
          'IPHONEOS_DEPLOYMENT_TARGET = 15.0;',
        ),
        'IPHONEOS_DEPLOYMENT_TARGET = 15.0, expected 16.0',
      ),
      'a deployment target removed': (
        NativeConfigPaths.pbxproj,
        (text) => text.replaceFirst('IPHONEOS_DEPLOYMENT_TARGET = 16.0;', ''),
        'appears 2 times',
      ),
      'Podfile platform': (
        podfile,
        _replace("platform :ios, '16.0'", "platform :ios, '15.0'"),
        'platform :ios is 15.0',
      ),
      'Podfile iOSVersion': (
        podfile,
        _replace(r"$iOSVersion = '16.0'", r"$iOSVersion = '15.0'"),
        r'$iOSVersion is 15.0',
      ),
      'Podfile armv7': (
        podfile,
        _replace("= 'armv7'", "= 'x86'"),
        'missing EXCLUDED_ARCHS',
      ),
      'Podfile template call': (
        podfile,
        _replace(
          '    flutter_additional_ios_build_settings(target)',
          '    # flutter_additional_ios_build_settings(target)',
        ),
        'missing flutter_additional_ios_build_settings',
      ),
      'debug xcconfig without pods': (
        NativeConfigPaths.debugXcconfig,
        (text) => text.split('\n').skip(1).join('\n'),
        'debug xcconfig: the first line must be #include?',
      ),
      'release xcconfig not optional': (
        NativeConfigPaths.releaseXcconfig,
        _replace('#include? "Pods', '#include "Pods'),
        'release xcconfig: the first line must be #include?',
      ),
      'release xcconfig without Generated': (
        NativeConfigPaths.releaseXcconfig,
        _replace('#include "Generated.xcconfig"', ''),
        'release xcconfig: missing #include "Generated.xcconfig"',
      ),
      'gradle: another properties file': (
        NativeConfigPaths.androidGradle,
        _replace(
          'rootProject.file("key.properties")',
          'file("key.properties")',
        ),
        // Without the variable the two branches are not found either.
        [
          'build.gradle.kts: reads (nothing), expected rootProject.file("key.properties")',
          'create("release") must sit in if (',
          'release must use signingConfigs "release"',
        ],
      ),
      'gradle: release signing without the guard': (
        NativeConfigPaths.androidGradle,
        _replace(
          'if (keystorePropertiesFile.exists()) {\n            create("release")',
          'run {\n            create("release")',
        ),
        'create("release") must sit in if (<key.properties file>.exists())',
      ),
      'gradle: a signing property not read': (
        NativeConfigPaths.androidGradle,
        _replace(
          'keyPassword = keystoreProperties.getProperty("keyPassword")',
          '',
        ),
        'the release signing config does not read keyPassword',
      ),
      'gradle: release always on the debug key (1차)': (
        NativeConfigPaths.androidGradle,
        _replace(
          'signingConfig = if (keystorePropertiesFile.exists())\n'
              '                signingConfigs.getByName("release") else '
              'signingConfigs.getByName("debug")',
          'signingConfig = signingConfigs.getByName("debug")',
        ),
        'release must use signingConfigs "release" when key.properties '
            'exists, else "debug"',
      ),
    };
    for (final MapEntry(key: name, value: (path, edit, expected))
        in cases.entries) {
      test(name, () {
        final problems = appNativeConfigProblems(_withEdit(path, edit));
        final wanted = expected is List<String>
            ? expected
            : [expected as String];
        expect(problems, hasLength(wanted.length), reason: problems.join('\n'));
        for (final (i, text) in wanted.indexed) {
          expect(problems[i], contains(text));
        }
      });
    }
  });

  group('tool/native_requirements.yaml fully met (J1 — NR7)', () {
    late NativeConfig config;
    late NativeRequirements requirements;
    setUpAll(() {
      config = NativeConfig.load(repoRoot);
      requirements = NativeRequirements.load(
        p.join(repoRoot, NativeReqsPaths.requirements),
      );
    });

    test('no problem on the committed files', () {
      expect(nativeRequirementProblems(requirements, config), isEmpty);
    });

    test('build.gradle.kts keeps Flutter\'s default SDK levels', () {
      expect(config.androidGradle.minSdk, gradleFlutterDefault);
      expect(config.androidGradle.compileSdk, gradleFlutterDefault);
    });

    test('the requirements file and AppNativeExpectations agree', () {
      final app = requirements.app;
      expect(
        app.iosDeploymentTarget,
        AppNativeExpectations.iosDeploymentTarget,
      );
      expect(app.androidLabel, AppNativeExpectations.displayName);
      expect(app.iosDisplayName, AppNativeExpectations.displayName);
      expect(app.androidAllowBackup, isFalse);
      final plugins = requirements.plugins.values;
      expect({
        ...requirements.appExtraAndroidPermissions,
        for (final r in plugins) ...r.androidPermissions,
      }, AppNativeExpectations.androidPermissions);
      expect({
        for (final r in plugins)
          for (final c in r.androidRemoved)
            if (c.tag == 'uses-permission') c.name,
      }, AppNativeExpectations.androidRemovedPermissions);
      expect(
        {
          for (final r in plugins)
            for (final c in r.androidRemoved)
              if (c.tag == 'receiver') c.name,
        },
        {AppNativeExpectations.rebootReceiver},
      );
      final service = plugins.expand((r) => r.androidServices).single;
      expect(service.name, AppNativeExpectations.foregroundService);
      expect({
        for (final MapEntry(:key, :value) in service.attributes.entries)
          'android:$key': value,
      }, AppNativeExpectations.foregroundServiceAttributes);
      expect(
        {for (final r in plugins) ...r.iosPlistKeys},
        AppNativeExpectations.iosStrings.keys.toSet()
          ..remove('CFBundleDisplayName'),
      );
      expect({
        for (final r in plugins) ...r.iosBackgroundModes,
      }, AppNativeExpectations.iosBackgroundModes);
      expect(requirements.appExtraIosPlist, AppNativeExpectations.iosBooleans);
    });

    test('a plugin requirement removed from the committed manifest is one '
        'line', () {
      final broken = _withEdit(
        NativeConfigPaths.androidManifest,
        _replace(
          '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
          '',
        ),
      );
      expect(nativeRequirementProblems(requirements, broken), [
        'AndroidManifest: missing <uses-permission android.permission.RECORD_AUDIO>',
      ]);
    });
  });

  group('app shell storage paths (J4 — 6.9, contract 7.2.6)', () {
    late AppShellStorageSources committed;
    setUpAll(() => committed = AppShellStorageSources.load(repoRoot));

    /// [committed] with one file's text changed.
    AppShellStorageSources edit(String path, String Function(String) change) =>
        committed.withFile(path, change(committed.files[path]!));

    group('dartTokens', () {
      test('comments (nested) dropped, strings one token, operators', () {
        expect(
          dartTokens(
            "a?.b ?? c; /* x /* y */ z */ d => 'q' // e\n"
            r"r'\n' "
            '"""t\'s""" ...f ??= 1.5;',
          ),
          [
            'a', '?.', 'b', '??', 'c', ';', 'd', '=>', "'q'", r"'\n'", //
            "'t's'", '...', 'f', '??=', '1.5', ';',
          ],
        );
      });

      test('generics and a conditional export', () {
        expect(
          dartTokens(
            "export 'a.dart'\n    if (dart.library.io) 'b.dart' show f;\n"
            'Future<X?> g() async => null;',
          ),
          [
            'export', "'a.dart'", 'if', '(', 'dart', '.', 'library', '.', //
            'io', ')', "'b.dart'", 'show', 'f', ';', 'Future', '<', 'X', '?',
            '>', 'g', '(', ')', 'async', '=>', 'null', ';',
          ],
        );
      });
    });

    test('the committed app/lib passes every rule', () {
      expect(committed.files, contains(AppShellStoragePaths.nativeFile));
      expect(appShellStoragePathProblems(committed), isEmpty);
    });

    test('comments and formatting do not matter', () {
      final sources = edit(
        AppShellStoragePaths.productionModules,
        _replace(
          'List<AppModule> productionModules() => [',
          'List<AppModule> productionModules() => [\n'
              '  // CoreModule(nativePaths: x) is not used here.\n',
        ),
      );
      expect(appShellStoragePathProblems(sources), isEmpty);
    });

    final cases = <String, (String, String Function(String), String)>{
      'export without the dart.library.io condition': (
        AppShellStoragePaths.barrel,
        _replace('if (dart.library.io)', 'if (dart.library.js_interop)'),
        'must export',
      ),
      'the stub does not define resolveNativeStoragePaths': (
        AppShellStoragePaths.stubFile,
        _replace('resolveNativeStoragePaths() async', 'resolvePaths() async'),
        'native_storage_paths_stub.dart: must define',
      ),
      'another lib file imports path_provider': (
        AppShellStoragePaths.coreModule,
        _replace(
          "import 'dart:async';",
          "import 'dart:async';\n"
              "import 'package:path_provider/path_provider.dart';",
        ),
        'core_module.dart: imports package:path_provider/',
      ),
      'another lib file imports the native file directly': (
        AppShellStoragePaths.coreModule,
        _replace(
          "import '../storage/native_storage_paths.dart';",
          "import '../storage/native_storage_paths_native.dart';",
        ),
        'core_module.dart: names native_storage_paths_native.dart',
      ),
      'the native file without path_provider': (
        AppShellStoragePaths.nativeFile,
        _replace(
          "import 'package:path_provider/path_provider.dart'\n"
              '    show getApplicationSupportDirectory;',
          '',
        ),
        'native_storage_paths_native.dart: must import',
      ),
      'nativeAssetDirectoryPath dropped (the 1st-round bug)': (
        AppShellStoragePaths.coreModule,
        _replace(
          '    nativeAssetDirectoryPath: paths?.assetDirectoryPath,\n',
          '',
        ),
        'nativeAssetDirectoryPath: must be set exactly once (found 0)',
      ),
      'nativeDatabasePath from somewhere else': (
        AppShellStoragePaths.coreModule,
        _replace(
          'nativeDatabasePath: paths?.databasePath,',
          "nativeDatabasePath: '/tmp/noteapp.sqlite',",
        ),
        'nativeDatabasePath: must be <paths>?.databasePath',
      ),
      'the two fields from two different values': (
        AppShellStoragePaths.coreModule,
        (text) =>
            _replace(
              'final paths = context.maybe<NativeStoragePaths>();',
              'final paths = context.maybe<NativeStoragePaths>();\n'
                  '  final other = context.maybe<NativeStoragePaths>();',
            )(
              _replace(
                'nativeAssetDirectoryPath: paths?.assetDirectoryPath,',
                'nativeAssetDirectoryPath: other?.assetDirectoryPath,',
              )(text),
            ),
        'must come from the same NativeStoragePaths value',
      ),
      'CoreModule defaults to another path function': (
        AppShellStoragePaths.coreModule,
        _replace(
          'this._nativePaths = resolveNativeStoragePaths,',
          'this._nativePaths = _noPaths,',
        ),
        'CoreModule(nativePaths:) must default to resolveNativeStoragePaths',
      ),
      'CoreModule defaults to another config': (
        AppShellStoragePaths.coreModule,
        _replace(
          'this._configFor = defaultNoteStoreConfig,',
          'this._configFor = _inMemory,',
        ),
        'CoreModule(configFor:) must default to defaultNoteStoreConfig',
      ),
      'productionModules() passes nativePaths': (
        AppShellStoragePaths.productionModules,
        _replace(
          '=> [\n  CoreModule(),',
          '=> [\n  CoreModule(nativePaths: _noPaths),',
        ),
        'productionModules() must construct CoreModule() with no argument',
      ),
      'modulesFor() passes configFor': (
        AppShellStoragePaths.productionModules,
        _replace(
          'core ?? CoreModule(),',
          'core ?? CoreModule(configFor: _inMemory),',
        ),
        'modulesFor() must construct CoreModule() with no argument',
      ),
    };
    for (final MapEntry(key: name, value: (path, change, expected))
        in cases.entries) {
      test(name, () {
        final problems = appShellStoragePathProblems(edit(path, change));
        expect(problems, hasLength(1), reason: problems.join('\n'));
        expect(problems.single, contains(expected));
      });
    }

    test('a missing file is one line', () {
      final problems = appShellStoragePathProblems(
        committed.withFile(AppShellStoragePaths.stubFile, null),
      );
      expect(problems, ['${AppShellStoragePaths.stubFile}: missing']);
    });
  });
}

/// FLUTTER_ROOT from `flutter` on PATH (null when not found).
String? _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    final flutter = File(p.join(dir, 'flutter'));
    if (flutter.existsSync()) {
      return p.dirname(p.dirname(flutter.resolveSymbolicLinksSync()));
    }
  }
  return null;
}
