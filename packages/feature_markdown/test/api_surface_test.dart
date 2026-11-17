// API surface of feature_markdown (08-markdown 12.2, contract 00-overview 7.9 C217M-14 /
// C217M-15). Fixed in the foundation: Track B may add inside src/, never rename these.
//
// 1. Entry points: exactly feature_markdown.dart and slots.dart; each shows exactly its names;
//    slots.dart reaches no parser code (it is imported eagerly while the screen is deferred).
// 2. Compile-time shape of every public member.
// 3. The screen builds on the fake store (back, title, rendered text, not-an-MD-문서).
@TestOn('vm')
library;

import 'dart:io';

import 'package:feature_markdown/feature_markdown.dart';
import 'package:feature_markdown/slots.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

Set<String> _shown(String path) {
  final source = File(path).readAsStringSync();
  final names = <String>{};
  final directive = RegExp(
    r'''^export\s+'[^']+'\s+show([^;]*);''',
    multiLine: true,
  );
  for (final m in directive.allMatches(source)) {
    for (final n in m.group(1)!.split(',')) {
      if (n.trim().isNotEmpty) names.add(n.trim());
    }
  }
  expect(
    RegExp(r'^export\s', multiLine: true).allMatches(source).length,
    directive.allMatches(source).length,
    reason: '$path: every export uses show',
  );
  return names;
}

/// Files [path] reaches through relative imports / exports inside lib/.
Set<String> _reach(String path, [Set<String>? seen]) {
  final out = seen ?? <String>{};
  if (!out.add(path)) return out;
  final source = File(path).readAsStringSync();
  for (final m in RegExp(
    r'''^(?:import|export)\s+'([^':]+)'.*;''',
    multiLine: true,
  ).allMatches(source)) {
    _reach(File(path).parent.uri.resolve(m.group(1)!).toFilePath(), out);
  }
  return out;
}

void main() {
  test('two entry points', () {
    final entries = Directory('lib')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.dart'))
        .toSet();
    expect(entries, {'feature_markdown.dart', 'slots.dart'});
  });

  test('each entry point shows exactly its names', () {
    expect(_shown('lib/feature_markdown.dart'), {
      'MarkdownScreen',
      'MarkdownKeys',
    });
    expect(_shown('lib/slots.dart'), {
      'MarkdownExportAction',
      'markdownExportActionProvider',
      'MarkdownOpenLinkAction',
      'markdownOpenLinkProvider',
    });
  });

  test('slots.dart never reaches the parser or the screen', () {
    for (final f in _reach('lib/slots.dart')) {
      final source = File(f).readAsStringSync();
      expect(source, isNot(contains('package:markdown/')), reason: f);
      expect(f, isNot(contains('markdown_screen')), reason: f);
    }
  });

  test('compile-time shape', () {
    const screen = MarkdownScreen(
      noteId: 'n',
      initialQuery: 'q',
      initialEdit: true,
      onClose: _noop,
      onOpenAsNote: _noop,
    );
    expect(screen.noteId, 'n');
    expect(screen.initialQuery, 'q');
    expect(screen.initialEdit, isTrue);
    expect(
      const MarkdownScreen(noteId: 'n', onClose: _noop).initialEdit,
      isFalse,
    );
    final Provider<MarkdownExportAction?> export = markdownExportActionProvider;
    final Provider<MarkdownOpenLinkAction?> open = markdownOpenLinkProvider;
    expect(export.name, 'markdownExportActionProvider');
    expect(open.name, 'markdownOpenLinkProvider');
    Future<void> exportAction(
      BuildContext context, {
      required String title,
      required String text,
    }) async {}
    Future<bool> openAction(Uri uri) async => false;
    final MarkdownExportAction e = exportAction;
    final MarkdownOpenLinkAction o = openAction;
    expect([e, o], hasLength(2));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(markdownExportActionProvider), isNull);
    expect(container.read(markdownOpenLinkProvider), isNull);
  });

  test('keys: 08-markdown 13 names', () {
    expect(MarkdownKeys.screen.value, 'md.screen');
    expect(MarkdownKeys.mode.value, 'md.mode');
    expect(MarkdownKeys.editor.value, 'md.editor');
    expect(MarkdownKeys.view.value, 'md.view');
    expect(MarkdownKeys.bannerReceiving.value, 'md.banner.receiving');
    expect(MarkdownKeys.linkSheetOpen.value, 'md.linkSheet.open');
    expect(MarkdownKeys.leaveDialog.value, 'md.leave');
    expect(MarkdownKeys.highlight.value, 'md.highlight');
    expect(MarkdownKeys.task(3).value, 'md.task.3');
    expect(MarkdownKeys.codeCopy(1).value, 'md.code.1.copy');
    expect(MarkdownKeys.image(0).value, 'md.image.0');
  });

  testWidgets(
    'screen: title and rendered text of an MD 문서, back calls onClose',
    (tester) async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final note = await tester.runAsync(
        () => store.markdown.create(title: '문서', text: '# 안녕'),
      );
      final ink = await tester.runAsync(
        () => store.library.createNote(title: '필기'),
      );
      var closed = 0;
      var asNote = 0;
      Future<void> show(NoteId id) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [noteStoreProvider.overrideWithValue(store)],
            child: MaterialApp(
              home: MarkdownScreen(
                key: ValueKey(id),
                noteId: id,
                onClose: () => closed++,
                onOpenAsNote: () => asNote++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(note!.id);
      expect(find.byKey(MarkdownKeys.screen), findsOneWidget);
      expect(find.text('문서'), findsOneWidget);
      expect(find.text('안녕', findRichText: true), findsOneWidget);
      await tester.tap(find.byKey(MarkdownKeys.back));
      expect(closed, 1);

      await show(ink!.id);
      expect(find.byKey(MarkdownKeys.notMarkdown), findsOneWidget);
      await tester.tap(find.byKey(MarkdownKeys.openAsNote));
      expect(asNote, 1);
    },
  );
}

void _noop() {}
