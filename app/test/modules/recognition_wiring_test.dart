// Recognition actions → editor slots (docs/plans/m5-7/01-infra.md 4.6.5, 6.7
// '자리 변환'; contract 7.3.1 X30 v2.1 — CP13 승인, 7.2.10 v2.1 '자리
// 콜백 동기 시작'). Every RecognitionTarget field of the 6.7 table, the two
// `done` branches (selection → clearSelection; insert → select the last
// added object, or nothing), the insert `execute` wrapper (AddObjects, inside
// CompositeCommand, no addition, a throwing command) and the menu items
// calling `run` synchronously.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart'
    show
        EditorInsertContext,
        EditorMathConvertTrigger,
        EditorMathGroup,
        EditorMathPenContext,
        EditorSelectionContext;
import 'package:feature_library/feature_library.dart'
    show LibraryInkSearch, LibraryInkSearchPhase, LibraryInkSearchState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/modules/recognition_wiring.dart';

const _page = PageSize.a4Portrait;

final class _FakeBuildContext extends Fake implements BuildContext {}

/// Records what the editor side receives.
final class _Editor {
  final List<EditCommand> executed = [];
  final List<String> selected = [];
  int cleared = 0;

  /// Throws on the next execute when set.
  Error? failNext;

  void execute(EditCommand command) {
    if (failNext case final error?) {
      failNext = null;
      throw error;
    }
    executed.add(command);
  }

  EditorSelectionContext selection({
    List<Stroke> strokes = const [],
    List<PageObject> objects = const [],
  }) => EditorSelectionContext(
    noteId: 'n1',
    pageId: 'p1',
    pageSize: _page,
    strokes: strokes,
    objects: objects,
    boundsPt: const Rect.fromLTWH(10, 20, 300, 40),
    execute: execute,
    clearSelection: () => cleared++,
  );

  EditorInsertContext insert() => EditorInsertContext(
    noteId: 'n1',
    pageId: 'p1',
    pageSize: _page,
    visibleRectPt: const Rect.fromLTWH(0, 100, 595, 400),
    execute: execute,
    selectObject: selected.add,
  );
}

PageObject _math(String id) => PageObjectFixtures.math(pageId: 'p1', id: id);

PageObject _text(String id) => PageObjectFixtures.textBox(pageId: 'p1', id: id);

void main() {
  group('recognitionTargetOfSelection — the 6.7 table, selection column', () {
    test('noteId, pageId, pageSize, strokes, objects, areaPt = boundsPt, '
        'execute as is, done = clearSelection', () {
      final editor = _Editor();
      final ids = SequentialIdGenerator();
      final stroke = StrokeFixtures.synthetic(pageId: 'p1', ids: ids);
      final object = _text('t1');
      final selection = editor.selection(strokes: [stroke], objects: [object]);
      final target = recognitionTargetOfSelection(selection);

      expect(
        (target.noteId, target.pageId, target.pageSize),
        ('n1', 'p1', _page),
      );
      expect(target.strokes, same(selection.strokes));
      expect(target.objects, same(selection.objects));
      expect(target.areaPt, selection.boundsPt);
      expect(target.execute, same(selection.execute));
      expect(target.done, same(selection.clearSelection));

      final command = RemoveElements(pageId: 'p1', elementIds: [object.id]);
      target.execute(command);
      expect(editor.executed, [same(command)]);
      target.done();
      expect(editor.cleared, 1);
      expect(editor.selected, isEmpty);
    });
  });

  group('recognitionTargetOfInsert — the 6.7 table, insert column', () {
    test('noteId, pageId, pageSize; no strokes, no objects; areaPt = '
        'visibleRectPt; execute forwards the command', () {
      final editor = _Editor();
      final insert = editor.insert();
      final target = recognitionTargetOfInsert(insert);
      expect(
        (target.noteId, target.pageId, target.pageSize),
        ('n1', 'p1', _page),
      );
      expect(target.strokes, isEmpty);
      expect(target.objects, isEmpty);
      expect(target.areaPt, insert.visibleRectPt);
      final command = AddObjects(pageId: 'p1', objects: [_math('m1')]);
      target.execute(command);
      expect(editor.executed, [same(command)]);
    });

    test('done after AddObjects → selectObject(the last added object)', () {
      final editor = _Editor();
      final target = recognitionTargetOfInsert(editor.insert());
      target.execute(
        AddObjects(pageId: 'p1', objects: [_math('m1'), _math('m2')]),
      );
      target.done();
      expect(editor.selected, ['m2']);
      expect(editor.cleared, 0);
    });

    test('inside CompositeCommand (nested too) the last added object wins', () {
      final editor = _Editor();
      final target = recognitionTargetOfInsert(editor.insert());
      target.execute(
        CompositeCommand([
          AddObjects(pageId: 'p1', objects: [_math('m1')]),
          CompositeCommand([
            AddObjects(pageId: 'p1', objects: [_math('m2')]),
            const RemoveElements(pageId: 'p1', elementIds: ['old']),
          ]),
        ]),
      );
      target.done();
      expect(editor.selected, ['m2']);
    });

    test('a later command that adds nothing keeps the remembered id; a later '
        'addition replaces it', () {
      final editor = _Editor();
      final target = recognitionTargetOfInsert(editor.insert());
      target.execute(AddObjects(pageId: 'p1', objects: [_math('m1')]));
      target.execute(const RemoveElements(pageId: 'p1', elementIds: ['x']));
      target.done();
      expect(editor.selected, ['m1']);
      target.execute(AddObjects(pageId: 'p1', objects: [_text('t9')]));
      target.done();
      expect(editor.selected, ['m1', 't9']);
    });

    test('no addition → done does nothing', () {
      final editor = _Editor();
      final target = recognitionTargetOfInsert(editor.insert());
      target.done();
      target.execute(const RemoveElements(pageId: 'p1', elementIds: ['x']));
      target.execute(const AddObjects(pageId: 'p1', objects: []));
      target.execute(const CompositeCommand([]));
      target.done();
      expect(editor.selected, isEmpty);
      expect(editor.cleared, 0);
    });

    test('a throwing command adds nothing: the error reaches the caller and '
        'done selects nothing', () {
      final editor = _Editor()..failNext = StateError('read-only');
      final target = recognitionTargetOfInsert(editor.insert());
      expect(
        () => target.execute(AddObjects(pageId: 'p1', objects: [_math('m1')])),
        throwsStateError,
      );
      target.done();
      expect(editor.selected, isEmpty);
    });
  });

  group('menu items', () {
    RecognitionAction action(
      String id, {
      required void Function(RecognitionTarget target) onRun,
      Completer<void>? gate,
      bool Function(RecognitionTarget target)? isVisible,
    }) => RecognitionAction(
      id: id,
      label: '라벨 $id',
      icon: Icons.functions,
      run: (context, target) {
        onRun(target);
        return gate?.future ?? Future<void>.value();
      },
      isVisible: isVisible,
    );

    test('selectionMenuItemOf: id, label, icon; onSelected calls run '
        'synchronously (before any microtask) with the selection target and '
        'returns its Future', () async {
      final editor = _Editor();
      RecognitionTarget? got;
      final gate = Completer<void>();
      final item = selectionMenuItemOf(
        action('recog.toText', onRun: (t) => got = t, gate: gate),
      );
      expect(
        (item.id, item.label, item.icon),
        ('recog.toText', '라벨 recog.toText', Icons.functions),
      );
      expect(item.isVisible, isNull);

      var finished = false;
      final selection = editor.selection(objects: [_text('t1')]);
      unawaited(
        item
            .onSelected(_FakeBuildContext(), selection)
            .then((_) => finished = true),
      );
      expect(got, isNotNull, reason: 'run started inside onSelected');
      expect(got!.objects, same(selection.objects));
      got!.done();
      expect(editor.cleared, 1);
      await pumpEventQueue();
      expect(finished, isFalse, reason: 'the Future is run\'s own');
      gate.complete();
      await pumpEventQueue();
      expect(finished, isTrue);
    });

    test('selectionMenuItemOf: isVisible reads the same target fields', () {
      final editor = _Editor();
      final item = selectionMenuItemOf(
        action(
          'recog.toMath',
          onRun: (_) {},
          isVisible: (t) => t.objects.isEmpty && t.areaPt.width > 100,
        ),
      );
      expect(item.isVisible!(editor.selection()), isTrue);
      expect(
        item.isVisible!(editor.selection(objects: [_text('t1')])),
        isFalse,
      );
    });

    test('insertMenuItemOf: id, label, icon; onSelected calls run '
        'synchronously with the insert target; its done selects the object '
        'the action added; isVisible is not used', () async {
      final editor = _Editor();
      RecognitionTarget? got;
      final item = insertMenuItemOf(
        action('recog.mathPad', onRun: (t) => got = t, isVisible: (_) => false),
      );
      expect(
        (item.id, item.label, item.icon),
        ('recog.mathPad', '라벨 recog.mathPad', Icons.functions),
      );
      final pending = item.onSelected(_FakeBuildContext(), editor.insert());
      expect(got, isNotNull, reason: 'run started inside onSelected');
      expect(got!.areaPt, const Rect.fromLTWH(0, 100, 595, 400));
      got!.execute(AddObjects(pageId: 'p1', objects: [_math('m7')]));
      got!.done();
      expect(editor.selected, ['m7']);
      await pending;
    });
  });

  // (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 11.1)
  group('editorMathPenOf — recog\'s math pen as the editor slot', () {
    test('context, groups as targets, triggers → interactive, fix → the '
        'formula target', () async {
      final editor = _Editor();
      final inner = _RecordingMathPenSession();
      RecognitionMathPenContext? got;
      final slot = editorMathPenOf(
        RecognitionMathPen(
          open: (context) {
            got = context;
            return inner;
          },
        ),
      );
      List<Stroke>? live(String pageId, List<String> ids) => const [];
      BuildContext? body() => null;
      final session = slot.open(
        EditorMathPenContext(
          noteId: 'n1',
          pageSizeOf: (id) => id == 'p1' ? _page : null,
          execute: editor.execute,
          liveStrokes: live,
          bodyContext: body,
        ),
      );
      expect(got!.noteId, 'n1');
      expect(got!.liveStrokes, same(live));
      expect(got!.bodyContext, same(body));
      got!.execute(RemoveElements(pageId: 'p1', elementIds: const ['x']));
      expect(editor.executed, hasLength(1));

      final stroke = StrokeFixtures.synthetic(
        pageId: 'p1',
        ids: SequentialIdGenerator(prefix: 's'),
      );
      final formula = _math('m1') as MathObject;
      final group = EditorMathGroup(
        pageId: 'p1',
        strokes: [stroke],
        boundsPt: const Rect.fromLTWH(1, 2, 3, 4),
        reopenedFrom: formula,
        reopenedStrokeIds: {stroke.id},
      );
      session.update(group);
      final target = inner.updates.single;
      expect(target.noteId, 'n1');
      expect(target.pageId, 'p1');
      expect(target.pageSize, _page);
      expect(target.strokes, [stroke]);
      expect(target.areaPt, const Rect.fromLTWH(1, 2, 3, 4));
      expect(inner.reopened, [formula]);
      expect(inner.reopenedIds.single, {stroke.id});

      await session.convert(group, EditorMathConvertTrigger.bubbleTap);
      bool wanted() => true;
      await session.convert(
        group,
        EditorMathConvertTrigger.toolSwitch,
        stillWanted: wanted,
      );
      await session.convert(group, EditorMathConvertTrigger.newGroup);
      expect(inner.interactive, [true, false, false]);
      // The editor's history guard goes through unchanged.
      expect(inner.stillWanted, [null, wanted, null]);

      session
        ..interrupt()
        ..clear();
      expect(inner.calls, ['interrupt', 'clear']);
      await session.fix(formula);
      expect(inner.fixed.single.objects, [formula]);
      expect(inner.fixed.single.strokes, isEmpty);
      expect(session.changes, same(inner.changes));
      session.dispose();
      expect(inner.calls.last, 'dispose');
    });
  });

  group('(handwriting search) libraryInkSearchOf', () {
    test(
      'every recog phase maps to the library phase; unavailable → ready',
      () {
        final expected = {
          HandwritingSearchPhase.unavailable: LibraryInkSearchPhase.ready,
          HandwritingSearchPhase.ready: LibraryInkSearchPhase.ready,
          HandwritingSearchPhase.autoIndexOff:
              LibraryInkSearchPhase.autoIndexOff,
          HandwritingSearchPhase.modelMissing:
              LibraryInkSearchPhase.modelMissing,
          HandwritingSearchPhase.modelDownloading:
              LibraryInkSearchPhase.modelDownloading,
          HandwritingSearchPhase.waitingForWifi:
              LibraryInkSearchPhase.waitingForWifi,
          HandwritingSearchPhase.modelFailed: LibraryInkSearchPhase.modelFailed,
          HandwritingSearchPhase.indexing: LibraryInkSearchPhase.indexing,
        };
        expect(expected.keys, unorderedEquals(HandwritingSearchPhase.values));
        for (final MapEntry(key: from, value: to) in expected.entries) {
          expect(
            libraryInkSearchStateOf(HandwritingSearchStatus(phase: from)).phase,
            to,
            reason: '$from',
          );
        }
        expect(
          libraryInkSearchStateOf(
            const HandwritingSearchStatus(
              phase: HandwritingSearchPhase.indexing,
              remainingPages: 4,
              confirmCellularFirst: true,
            ),
          ),
          const LibraryInkSearchState(
            phase: LibraryInkSearchPhase.indexing,
            remainingPages: 4,
            confirmCellularFirst: true,
          ),
        );
      },
    );

    test('no indexer (no engine) → null', () {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final container = ProviderContainer.test(
        overrides: [noteStoreProvider.overrideWithValue(store)],
      );
      final slot = Provider<LibraryInkSearch?>(libraryInkSearchOf);
      expect(container.read(slot), isNull);
    });

    testWidgets(
      'with an engine: the state follows recog, the actions reach it',
      (tester) async {
        final store = createFakeNoteStore();
        addTearDown(store.close);
        await store.settings.set(
          SettingKey.boolean(
            'recog.autoIndex',
            true,
            scope: SettingScope.device,
          ),
          false,
        );
        final container = ProviderContainer.test(
          overrides: [
            noteStoreProvider.overrideWithValue(store),
            handwritingRecognizerProvider.overrideWithValue(
              FakeHandwritingRecognizer(),
            ),
          ],
        );
        final slot = Provider<LibraryInkSearch?>(libraryInkSearchOf);
        container.read(handwritingIndexerProvider)!.start();
        final ink = container.read(slot)!;
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }
        expect(ink.state.value.phase, LibraryInkSearchPhase.autoIndexOff);
        await ink.turnOnAutoIndex();
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }
        expect(ink.state.value.phase, LibraryInkSearchPhase.ready);
        ink.searchOpened(); // no throw
        container.dispose();
        await tester.pump();
      },
    );
  });
}

final class _RecordingMathPenSession implements RecognitionMathPenSession {
  final List<RecognitionTarget> updates = [];
  final List<MathObject?> reopened = [];
  final List<Set<String>> reopenedIds = [];
  final List<bool> interactive = [];
  final List<bool Function()?> stillWanted = [];
  final List<RecognitionTarget> fixed = [];
  final List<String> calls = [];
  final ValueNotifier<int> _changes = ValueNotifier(0);

  @override
  void update(
    RecognitionTarget group, {
    MathObject? reopenedFrom,
    Set<String> reopenedStrokeIds = const {},
  }) {
    updates.add(group);
    reopened.add(reopenedFrom);
    reopenedIds.add(reopenedStrokeIds);
  }

  @override
  void interrupt() => calls.add('interrupt');

  @override
  void clear() => calls.add('clear');

  @override
  Future<bool> convert(
    RecognitionTarget group, {
    required bool interactive,
    bool Function()? stillWanted,
  }) async {
    this.interactive.add(interactive);
    this.stillWanted.add(stillWanted);
    return false;
  }

  @override
  Future<void> fix(RecognitionTarget formula) async => fixed.add(formula);

  @override
  Listenable get changes => _changes;

  @override
  Widget buildBubble(
    BuildContext context,
    RecognitionTarget group,
    VoidCallback onConvert,
  ) => const SizedBox();

  @override
  void dispose() => calls.add('dispose');
}
