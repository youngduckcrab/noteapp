// BuildInfo (docs/plans/01-infra.md 4.5.1, 6.11 and 9.1). The plan's src/build/
// and test/build/ are named runtime/ here: build/ directories are build
// output for git, the analyzer and ws.

import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/src/runtime/build_info.dart';

void main() {
  const sha = '0123456789abcdef0123456789abcdef01234567';
  final json = <String, Object?>{
    'APP_VERSION': '0.1.0',
    'APP_BUILD_NUMBER': '42',
    'APP_GIT_SHA': sha,
    'APP_GIT_REF': 'main',
    'APP_CHANNEL': 'live',
    'APP_BUILD_TIME': '2026-11-04T09:10:00Z',
  };

  test('no defines: local', () {
    // `flutter test` passes no --dart-define, so every value falls back.
    final info = BuildInfo.fromEnvironment();
    expect(info, BuildInfo.local);
    expect(info.isLocal, isTrue);
    expect(info.channel, BuildChannel.local);
    expect(info.shortSha, 'local');
    expect(info.builtAt, isNull);
  });

  test('fromJson reads every APP_* key', () {
    final info = BuildInfo.fromJson(json);
    expect(info.version, '0.1.0');
    expect(info.buildNumber, 42);
    expect(info.gitSha, sha);
    expect(info.gitRef, 'main');
    expect(info.channel, BuildChannel.live);
    expect(info.builtAt, DateTime.utc(2026, 11, 4, 9, 10));
    expect(info.isLocal, isFalse);
  });

  test('JSON round trip (all values strings, ws build-info format)', () {
    final info = BuildInfo.fromJson(json);
    expect(info.toJson(), json);
    expect(BuildInfo.fromJson(info.toJson()), info);
    expect(info.toJson().values, everyElement(isA<String>()));
    final local = BuildInfo.local.toJson();
    expect(local.containsKey('APP_BUILD_TIME'), isFalse);
    expect(BuildInfo.fromJson(local), BuildInfo.local);
  });

  test('missing APP_GIT_SHA is a FormatException', () {
    expect(
      () => BuildInfo.fromJson({...json}..remove('APP_GIT_SHA')),
      throwsFormatException,
    );
    expect(
      () => BuildInfo.fromJson({...json, 'APP_GIT_SHA': ''}),
      throwsFormatException,
    );
    expect(
      () => BuildInfo.fromJson({...json, 'APP_GIT_SHA': 12}),
      throwsFormatException,
    );
  });

  test('malformed values fall back field by field', () {
    final info = BuildInfo.fromJson({
      'APP_GIT_SHA': sha,
      'APP_BUILD_NUMBER': 'forty-two',
      'APP_CHANNEL': 'production',
      'APP_BUILD_TIME': 'yesterday',
      'APP_VERSION': '',
    });
    expect(info.buildNumber, 0);
    expect(info.channel, BuildChannel.local);
    expect(info.builtAt, isNull);
    expect(info.version, '0.0.0');
    expect(info.gitRef, 'local');
    expect(
      BuildInfo.fromJson({'APP_GIT_SHA': sha, 'APP_BUILD_NUMBER': -1})
          .buildNumber,
      0,
    );
    expect(
      BuildInfo.fromJson({'APP_GIT_SHA': sha, 'APP_BUILD_NUMBER': 7})
          .buildNumber,
      7,
    );
    for (final channel in BuildChannel.values) {
      expect(
        BuildInfo.fromJson({'APP_GIT_SHA': sha, 'APP_CHANNEL': channel.name})
            .channel,
        channel,
      );
    }
  });

  test('displayLabel and shortSha', () {
    final info = BuildInfo.fromJson({...json, 'APP_GIT_SHA': 'a1b2c3d4e5f6'});
    expect(info.shortSha, 'a1b2c3d');
    expect(info.displayLabel, '0.1.0 (#42 · a1b2c3d · main)');
    expect(BuildInfo.local.displayLabel, '0.0.0 (#0 · local · local)');
    expect(BuildInfo.fromJson({...json, 'APP_GIT_SHA': 'abc'}).shortSha, 'abc');
  });
}
