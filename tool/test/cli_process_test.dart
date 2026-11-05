// End-to-end: `dart run tool/ws.dart` as a real process (entry point, exit
// codes, output). Tagged `process` (declared in the root dart_test.yaml).
@Tags(['process'])
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture_workspace.dart';

Future<ProcessResult> _ws(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['run', p.join(repoRoot, 'tool', 'ws.dart'), ...args],
  workingDirectory: repoRoot,
);

void main() {
  test('ws list on the real workspace', () async {
    final result = await _ws(['list']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final names = [
      for (final line in '${result.stdout}'.trim().split('\n'))
        line.split(RegExp(r'\s+')).first,
    ];
    expect(names, [
      'note_core',
      'ink_engine',
      'feature_editor',
      'feature_library',
      'pdf_io',
      'sync_engine',
      'ink_lab',
      'media_io',
      'ink_recognition',
      'pencil_bridge',
      'noteapp',
    ]);
  });

  test('ws check exits 1 on a violating fixture, 2 on bad usage', () async {
    final fixture = FixtureWorkspace.clean({
      'packages/note_core/test/x_test.dart': "@Tags(['integration'])\n",
    });
    addTearDown(fixture.dispose);
    final result = await _ws([
      '--root',
      fixture.root,
      'check',
      '--no-exports',
      '--rules',
      realRulesPath,
    ]);
    expect(result.exitCode, 1);
    expect('${result.stdout}', contains('[R15]'));

    final usage = await _ws(['check', '--no-such-flag']);
    expect(usage.exitCode, 2);
  });

  test('SIGTERM stops ws test: the running flutter tree is killed, ws exits '
      '143 and does not start the next member', () async {
    // A fake `flutter` that starts a grandchild and waits (like flutter
    // test waiting for a hung Chrome), recording every start.
    final bin = Directory.systemTemp.createTempSync('ws_fake_flutter_');
    addTearDown(() => bin.deleteSync(recursive: true));
    final starts = File(p.join(bin.path, 'starts'));
    final flutter = File(p.join(bin.path, 'flutter'))
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'echo "\$PWD" >> "${starts.path}"\n'
        'sleep 300 &\n'
        'echo "grandchild \$!"\n'
        'wait\n',
      );
    Process.runSync('chmod', ['+x', flutter.path]);
    final fixture = FixtureWorkspace.clean({
      'packages/ink_engine/test/a_test.dart': '',
    });
    addTearDown(fixture.dispose);

    final ws = await Process.start(
      Platform.resolvedExecutable,
      [
        'run',
        p.join(repoRoot, 'tool', 'ws.dart'),
        '--root',
        fixture.root,
        'test',
      ],
      workingDirectory: repoRoot,
      environment: {'FLUTTER_BIN': flutter.path},
    );
    final output = StringBuffer();
    final grandchild = Completer<int>();
    ws.stdout.transform(const SystemEncoding().decoder).listen((chunk) {
      output.write(chunk);
      final match = RegExp(r'grandchild (\d+)').firstMatch('$output');
      if (match != null && !grandchild.isCompleted) {
        grandchild.complete(int.parse(match.group(1)!));
      }
    });
    ws.stderr.transform(const SystemEncoding().decoder).listen(output.write);
    final pid = await grandchild.future;

    expect(ws.kill(), isTrue); // SIGTERM to ws
    expect(await ws.exitCode, 143, reason: '$output');
    expect('$output', contains('stopping the running processes'));
    // note_core ran (and was killed); ink_engine was never started.
    expect(starts.readAsLinesSync(), [
      p.join(fixture.root, 'packages', 'note_core'),
    ]);
    while (_alive(pid)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }, skip: Platform.isLinux ? false : 'needs /proc and sh');
}

/// Whether [pid] is a live process (a zombie counts as gone).
bool _alive(int pid) {
  final stat = File('/proc/$pid/stat');
  if (!stat.existsSync()) return false;
  final text = stat.readAsStringSync();
  final state = text.substring(text.lastIndexOf(')') + 2).split(' ').first;
  return state != 'Z' && state != 'X';
}
