// Workspace model and `ws list` (docs/plans/01-infra.md 4.2).

import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/rules.dart';
import '../src/workspace.dart';
import 'support/fixture_workspace.dart';

void main() {
  FixtureWorkspace? fixture;
  tearDown(() {
    fixture?.dispose();
    fixture = null;
  });

  test('members keep the workspace: order and expose their pubspec', () {
    fixture = FixtureWorkspace.clean();
    final ws = fixture!.load();
    expect(ws.declaredMemberPaths, [
      'app',
      'packages/note_core',
      'packages/ink_engine',
      'packages/feature_library',
    ]);
    expect(ws.members.map((m) => m.name), [
      'noteapp',
      'note_core',
      'ink_engine',
      'feature_library',
    ]);
    final ink = ws.memberNamed('ink_engine')!;
    expect(ink.path, 'packages/ink_engine');
    expect(ink.dependsOnFlutterSdk, isTrue);
    expect(ws.memberNamed('note_core')!.dependsOnFlutterSdk, isFalse);
    expect(ink.siblingDependencies(ws.memberNames), {'note_core'});
  });

  test('topological order puts dependencies first, ties in list order', () {
    fixture = FixtureWorkspace.clean();
    expect(fixture!.load().topologicalOrder().map((m) => m.name), [
      'note_core',
      'ink_engine',
      'feature_library',
      'noteapp',
    ]);
  });

  test('a dependency cycle is reported', () {
    fixture = FixtureWorkspace.clean({
      'packages/note_core/pubspec.yaml': '''
name: note_core
resolution: workspace
dev_dependencies:
  ink_engine: any
''',
    });
    expect(
      () => fixture!.load().topologicalOrder(),
      throwsA(
        isA<WorkspaceException>().having(
          (e) => e.message,
          'message',
          contains('dependency cycle'),
        ),
      ),
    );
  });

  test('findRoot walks up to the workspace pubspec', () {
    fixture = FixtureWorkspace.clean();
    expect(
      Workspace.findRoot('${fixture!.root}/packages/ink_engine/lib'),
      fixture!.root,
    );
  });

  test('the real workspace lists the 7 members of contract 7.1, the ink lab '
      '(7.1 optional row, INFRA-O1), the 3 service packages of 2차 7.1 '
      'v2.1 and the design layer ui_kit (v2.14-ui)', () {
    final ws = Workspace.load(repoRoot);
    expect(ws.topologicalOrder().map((m) => m.name), [
      'note_core',
      'ui_kit',
      'ink_engine',
      'feature_editor',
      'feature_library',
      'pdf_io',
      'sync_engine',
      'ink_lab',
      'media_io',
      'ink_recognition',
      'pencil_bridge',
      'feature_markdown', // v2.17-md
      'noteapp',
    ]);
    expect(ws.memberNamed('noteapp')!.path, 'app');
    expect(ws.memberNamed('ink_lab')!.path, 'packages/ink_engine/example');
    expect(ws.memberNamed('pencil_bridge')!.path, 'packages/pencil_bridge');
    // functions/ (SYNC, Node) is not a workspace member (contract 7.1 rule 6).
    expect(ws.declaredMemberPaths, isNot(contains('functions')));
  });

  test('a functions/ directory with only package.json is not a member and '
      'not an R1 violation (contract 7.1 rule 6)', () {
    fixture = FixtureWorkspace.clean({
      'functions/package.json': '{"name": "functions", "private": true}\n',
      'functions/src/index.ts': 'export {};\n',
      // Even a stray pubspec under functions/ is outside app/ and packages/.
      'functions/node_modules/x/pubspec.yaml':
          'name: x\nresolution: workspace\n',
    });
    final ws = fixture!.load();
    expect(ws.members.map((m) => m.name), isNot(contains('functions')));
    expect(checkWorkspace(ws, WorkspaceRules.load(realRulesPath)), isEmpty);
  });

  test('ws list prints name and path in topological order', () async {
    fixture = FixtureWorkspace.clean();
    final out = StringBuffer();
    final code = await runWs([
      'list',
    ], context: WsContext(root: fixture!.root, out: out, err: StringBuffer()));
    expect(code, 0);
    expect(out.toString().trimRight().split('\n'), [
      'note_core        packages/note_core',
      'ink_engine       packages/ink_engine',
      'feature_library  packages/feature_library',
      'noteapp          app',
    ]);
  });

  test('ws outside a workspace is an environment error (3)', () async {
    final err = StringBuffer();
    final code = await runWs(
      ['list'],
      context: WsContext(out: StringBuffer(), err: err, workingDirectory: '/'),
    );
    expect(code, environmentExitCode);
    expect(err.toString(), contains('no workspace pubspec.yaml'));
  });

  test('unknown commands and extra arguments are usage errors (2)', () async {
    fixture = FixtureWorkspace.clean();
    for (final args in [
      ['bogus'],
      ['list', 'extra'],
      ['check', '--nope'],
    ]) {
      final code = await runWs(
        args,
        context: WsContext(
          root: fixture!.root,
          out: StringBuffer(),
          err: StringBuffer(),
        ),
      );
      expect(code, usageExitCode, reason: '$args');
    }
  });
}
