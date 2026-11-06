// Static checks of the committed native configuration (V12 — docs/plans/
// m5-7/01-infra.md 6.10.1, 6.11.1–6.11.4, 9.1 and appendix B; contract
// 00-overview 7.4.3 v2.1). The container has no Android SDK or Xcode, so the
// manifest, Info.plist, Xcode project, Podfile and xcconfig files are read as
// text; the real builds are android.yml / ios-compile.yml (CI).
//
// J0 part: the parsers, the committed files and every rule of
// appNativeConfigProblems (each one broken on purpose once). Later parts of
// this file: build.gradle.kts signing branch (J2), native_requirements.yaml
// fully met (J1), the app shell's two native storage paths (J4 — 6.9).

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/native_config.dart';
import 'support/fixture_workspace.dart';

String _read(String path) => File(p.join(repoRoot, path)).readAsStringSync();

/// [NativeConfig] from the committed files with one file's text changed.
NativeConfig _withEdit(String path, String Function(String text) edit) {
  String text(String file) => file == path ? edit(_read(file)) : _read(file);
  return NativeConfig(
    manifest: AndroidManifestInfo.parse(
      text(NativeConfigPaths.androidManifest),
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

    test('Xcode project (6.11.1): IPHONEOS_DEPLOYMENT_TARGET = 15.5 exactly '
        '3 times, no 15.0', () {
      expect(config.deploymentTargets, ['15.5', '15.5', '15.5']);
      expect(
        _read(NativeConfigPaths.pbxproj),
        isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0;')),
      );
    });

    test('Podfile (6.11.2): the template plus the ML Kit lines', () {
      final podfile = config.podfile;
      expect(podfile.platformIos, '15.5');
      expect(podfile.iosVersion, '15.5');
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
          'IPHONEOS_DEPLOYMENT_TARGET = 15.5;',
          'IPHONEOS_DEPLOYMENT_TARGET = 15.0;',
        ),
        'IPHONEOS_DEPLOYMENT_TARGET = 15.0, expected 15.5',
      ),
      'a deployment target removed': (
        NativeConfigPaths.pbxproj,
        (text) => text.replaceFirst('IPHONEOS_DEPLOYMENT_TARGET = 15.5;', ''),
        'appears 2 times',
      ),
      'Podfile platform': (
        podfile,
        _replace("platform :ios, '15.5'", "platform :ios, '15.0'"),
        'platform :ios is 15.0',
      ),
      'Podfile iOSVersion': (
        podfile,
        _replace(r"$iOSVersion = '15.5'", r"$iOSVersion = '15.0'"),
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
