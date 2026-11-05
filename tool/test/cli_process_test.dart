// End-to-end: `dart run tool/ws.dart` as a real process (entry point, exit
// codes, output). Tagged `process` (declared in the root dart_test.yaml).
@Tags(['process'])
library;

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
      'noteapp',
      'sync_engine',
      'ink_lab',
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
}
