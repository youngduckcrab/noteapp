// flutter / Chrome executable lookup (docs/plans/01-infra.md 4.2).

import 'package:test/test.dart';

import '../src/flutter_runner.dart';

void main() {
  group('locateFlutter', () {
    String? locate(
      Map<String, String> env, {
      String resolved = '/usr/lib/dart/bin/dart',
      Set<String> files = const {},
    }) => locateFlutter(
      environment: env,
      resolvedExecutable: resolved,
      isFile: files.contains,
    );

    const all = {
      '/custom/flutter',
      '/froot/bin/flutter',
      '/sdk/bin/flutter',
      '/path/bin/flutter',
    };

    test('1. FLUTTER_BIN wins', () {
      expect(
        locate(
          {
            'FLUTTER_BIN': '/custom/flutter',
            'FLUTTER_ROOT': '/froot',
            'PATH': '/path/bin',
          },
          resolved: '/sdk/bin/cache/dart-sdk/bin/dart',
          files: all,
        ),
        '/custom/flutter',
      );
    });

    test('2. then FLUTTER_ROOT/bin/flutter', () {
      expect(
        locate(
          {'FLUTTER_ROOT': '/froot', 'PATH': '/path/bin'},
          resolved: '/sdk/bin/cache/dart-sdk/bin/dart',
          files: all,
        ),
        '/froot/bin/flutter',
      );
    });

    test('3. then the SDK of the running Dart VM', () {
      expect(
        locate(
          {'PATH': '/path/bin'},
          resolved: '/sdk/bin/cache/dart-sdk/bin/dart',
          files: all,
        ),
        '/sdk/bin/flutter',
      );
    });

    test('4. then PATH', () {
      expect(locate({'PATH': '/x:/path/bin'}, files: all), '/path/bin/flutter');
    });

    test('a FLUTTER_BIN that does not exist falls through', () {
      expect(
        locate({
          'FLUTTER_BIN': '/missing/flutter',
          'PATH': '/path/bin',
        }, files: all),
        '/path/bin/flutter',
      );
    });

    test('null when nothing is found', () {
      expect(locate({'PATH': '/nowhere'}), isNull);
    });
  });

  group('locateChrome', () {
    test('CHROME_EXECUTABLE is used as is', () {
      expect(
        locateChrome(
          environment: {
            'CHROME_EXECUTABLE': '/opt/chrome-wrapper',
            'PATH': '/usr/bin',
          },
          isFile: (_) => true,
        ),
        '/opt/chrome-wrapper',
      );
    });

    test('PATH names in order: google-chrome, -stable, chromium, '
        'chromium-browser', () {
      String? find(Set<String> files) =>
          locateChrome(environment: {'PATH': '/a:/b'}, isFile: files.contains);

      expect(find({'/b/google-chrome', '/a/chromium'}), '/b/google-chrome');
      expect(
        find({'/a/chromium', '/b/google-chrome-stable'}),
        '/b/google-chrome-stable',
      );
      expect(find({'/b/chromium-browser', '/a/chromium'}), '/a/chromium');
      expect(find({'/b/chromium-browser'}), '/b/chromium-browser');
      expect(find({}), isNull);
    });
  });
}
