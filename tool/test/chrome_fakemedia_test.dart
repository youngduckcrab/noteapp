// tool/chrome-fakemedia (docs/plans/m5-7/01-infra.md 6.13, contract
// 00-overview 7.4.6): the Chrome wrapper of `media`-tagged runs. A fake
// "chrome" script records the arguments it gets; no real Chrome starts.
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/test_command.dart';
import 'support/fixture_workspace.dart';

const _flags = [
  '--use-fake-device-for-media-stream',
  '--use-fake-ui-for-media-stream',
  '--autoplay-policy=no-user-gesture-required',
];

/// The candidate list of the real script (searched when
/// NOTEAPP_REAL_CHROME is not set).
const _candidates =
    '/usr/local/bin/chrome-nosandbox google-chrome google-chrome-stable '
    'chromium chromium-browser';

void main() {
  final wrapper = p.join(repoRoot, chromeFakeMediaPath);
  late Directory dir;
  late String argsFile;
  late String fakeChrome;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('chrome_fakemedia_');
    argsFile = p.join(dir.path, 'args');
    fakeChrome = p.join(dir.path, 'fake-chrome');
    File(fakeChrome).writeAsStringSync(
      '#!/usr/bin/env bash\n'
      'printf "%s\\n" "\$0" "\$@" > "$argsFile"\n',
    );
    Process.runSync('chmod', ['755', fakeChrome]);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// A copy of the wrapper whose candidate list is [names] (so the search
  /// can be tested without the real Chromes of the container).
  String copyWithCandidates(String names) {
    final text = File(wrapper).readAsStringSync();
    expect(text, contains('for c in $_candidates; do'));
    final copy = p.join(dir.path, 'chrome-fakemedia');
    File(copy)
        .writeAsStringSync(text.replaceFirst(_candidates, names), flush: true);
    Process.runSync('chmod', ['755', copy]);
    return copy;
  }

  test('bash -n passes, the file is executable and LF only', () {
    final check = Process.runSync('bash', ['-n', wrapper]);
    expect(check.exitCode, 0, reason: '${check.stderr}');
    final mode = File(wrapper).statSync().mode;
    expect(mode & 0x49, 0x49, reason: 'u+x, g+x, o+x (100755)');
    final bytes = File(wrapper).readAsBytesSync();
    expect(bytes, isNot(contains(13)), reason: 'no CR');
    expect(File(wrapper).readAsStringSync(), startsWith('#!/usr/bin/env bash'));
  });

  test('git keeps it as 100755 when it is tracked', () {
    final result = Process.runSync('git', [
      'ls-files',
      '--stage',
      chromeFakeMediaPath,
    ], workingDirectory: repoRoot);
    final line = '${result.stdout}'.trim();
    if (result.exitCode != 0 || line.isEmpty) {
      markTestSkipped('not tracked yet (or no git)');
      return;
    }
    expect(line, startsWith('100755 '));
  });

  test('NOTEAPP_REAL_CHROME: the three flags, then the original arguments '
      'in order', () {
    final result = Process.runSync(
      wrapper,
      ['--headless', '--remote-debugging-port=0', 'about:blank'],
      environment: {'NOTEAPP_REAL_CHROME': fakeChrome},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File(argsFile).readAsLinesSync(), [
      fakeChrome,
      ..._flags,
      '--headless',
      '--remote-debugging-port=0',
      'about:blank',
    ]);
  });

  test('without NOTEAPP_REAL_CHROME the first candidate on PATH is used', () {
    final bin = Directory(p.join(dir.path, 'bin'))..createSync();
    final chromium = p.join(bin.path, 'chromium');
    File(fakeChrome).copySync(chromium);
    Process.runSync('chmod', ['755', chromium]);
    final copy = copyWithCandidates('no-such-chrome-1 chromium');
    final result = Process.runSync(
      copy,
      ['x'],
      environment: {'PATH': '${bin.path}:/usr/bin:/bin'},
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File(argsFile).readAsLinesSync(), [chromium, ..._flags, 'x']);
  });

  test('NOTEAPP_REAL_CHROME naming the wrapper itself is ignored (no '
      'endless self start)', () {
    final bin = Directory(p.join(dir.path, 'bin'))..createSync();
    final chrome = p.join(bin.path, 'google-chrome');
    File(fakeChrome).copySync(chrome);
    Process.runSync('chmod', ['755', chrome]);
    final copy = copyWithCandidates('google-chrome');
    final result = Process.runSync(
      copy,
      ['y'],
      environment: {
        'PATH': '${bin.path}:/usr/bin:/bin',
        'NOTEAPP_REAL_CHROME': copy,
      },
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File(argsFile).readAsLinesSync().first, chrome);
  });

  test('no Chrome at all: exit code 3 and a message', () {
    final copy = copyWithCandidates('no-such-chrome-1 no-such-chrome-2');
    final result = Process.runSync(
      copy,
      const [],
      environment: {'PATH': '/usr/bin:/bin'},
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 3);
    expect('${result.stderr}', contains('chrome-fakemedia: no Chrome found'));
    expect(File(argsFile).existsSync(), isFalse);
  });
}
