// Temporary fake workspaces for the checker tests.
//
// Fixtures are written to a temp directory by each test instead of being
// committed as files: committed fixture `*_test.dart` files would be picked
// up by `dart test tool/test` itself.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../src/workspace.dart';

/// The repository root (the workspace root `dart test` runs from).
String get repoRoot {
  final root = Workspace.findRoot(Directory.current.path);
  if (root == null) {
    throw StateError('run `dart test tool/test` inside the repository');
  }
  return root;
}

/// Path of the real `tool/workspace_rules.yaml`.
String get realRulesPath => p.join(repoRoot, 'tool', 'workspace_rules.yaml');

/// A clean fixture workspace (no violation under the real rules file) with
/// four members: pure Dart `note_core`, Flutter `ink_engine` and
/// `feature_library`, and the app `noteapp`.
Map<String, String> cleanWorkspaceFiles() => {
  'pubspec.yaml': '''
name: fixture_workspace
publish_to: none
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
workspace:
  - app
  - packages/note_core
  - packages/ink_engine
  - packages/feature_library
dev_dependencies:
  test: 1.31.1
''',
  'packages/note_core/pubspec.yaml': '''
name: note_core
publish_to: none
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  riverpod: 3.4.3
dev_dependencies:
  test: 1.31.1
''',
  'packages/note_core/lib/note_core.dart': "export 'src/a.dart';\n",
  'packages/note_core/lib/src/a.dart': 'const a = 1;\n',
  'packages/note_core/test/a_test.dart': '''
import 'package:note_core/src/a.dart';
import 'package:test/test.dart';

void main() => test('a', () => expect(a, 1));
''',
  'packages/ink_engine/pubspec.yaml': '''
name: ink_engine
publish_to: none
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  flutter:
    sdk: flutter
  note_core: any
  riverpod: 3.4.3
dev_dependencies:
  flutter_test:
    sdk: flutter
''',
  'packages/ink_engine/lib/ink_engine.dart': '''
import 'package:flutter/widgets.dart';
import 'package:note_core/note_core.dart';
''',
  'packages/ink_engine/test/ink_test.dart': '''
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
''',
  'packages/feature_library/pubspec.yaml': '''
name: feature_library
publish_to: none
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  flutter:
    sdk: flutter
  note_core: any
  material_ui: 1.10.0
dev_dependencies:
  flutter_test:
    sdk: flutter
''',
  'packages/feature_library/lib/feature_library.dart': '''
import 'package:material_ui/material_ui.dart';
''',
  'app/pubspec.yaml': '''
name: noteapp
publish_to: none
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  flutter:
    sdk: flutter
  note_core: any
  ink_engine: any
  feature_library: any
  go_router: 18.1.2
dev_dependencies:
  flutter_test:
    sdk: flutter
''',
  'app/lib/main.dart': "import 'package:material_ui/material_ui.dart';\n",
};

/// A fake workspace on disk.
final class FixtureWorkspace {
  FixtureWorkspace._(this.root);

  /// Writes [files] (repo-relative path → content) into a new temp directory.
  factory FixtureWorkspace.create(Map<String, String> files) {
    final dir = Directory.systemTemp.createTempSync('ws_fixture_');
    final fixture = FixtureWorkspace._(dir.path);
    files.forEach(fixture.write);
    return fixture;
  }

  /// The clean workspace of [cleanWorkspaceFiles], with [overrides] applied
  /// (a `null` value deletes the file).
  factory FixtureWorkspace.clean([Map<String, String?> overrides = const {}]) {
    final files = cleanWorkspaceFiles();
    final fixture = FixtureWorkspace.create(files);
    overrides.forEach((path, content) {
      if (content == null) {
        fixture.delete(path);
      } else {
        fixture.write(path, content);
      }
    });
    return fixture;
  }

  final String root;

  void write(String path, String content) {
    final file = File(p.join(root, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void delete(String path) {
    final file = File(p.join(root, path));
    if (file.existsSync()) file.deleteSync();
  }

  Workspace load() => Workspace.load(root);

  void dispose() => Directory(root).deleteSync(recursive: true);
}
