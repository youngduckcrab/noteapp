// (handwriting search, 05-library 6.19a) the library search's handwriting
// hint: nothing without the slot or when ready; one line + its action per
// phase in the empty search state and above the results; [켜기] and
// [지금 받기] (two presses when it would use cellular data); opening the
// search tells the slot (searchOpened).
import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/ui/content/ink_search_hint.dart';
import 'package:feature_library/src/ui/content/search_results_view.dart';
import 'package:feature_library/src/ui/top_bar/library_search_field.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';

final class _FakeInkSearch implements LibraryInkSearch {
  _FakeInkSearch(LibraryInkSearchState initial)
    : _state = ValueNotifier(initial);

  final ValueNotifier<LibraryInkSearchState> _state;
  final List<String> calls = [];

  set value(LibraryInkSearchState v) => _state.value = v;

  @override
  ValueListenable<LibraryInkSearchState> get state => _state;

  @override
  Future<void> turnOnAutoIndex() async => calls.add('turnOn');

  @override
  Future<void> downloadModel({bool cellular = false}) async =>
      calls.add('download(cellular: $cellular)');

  @override
  void searchOpened() => calls.add('opened');
}

final Finder _searchInput = find.descendant(
  of: find.byType(LibrarySearchField),
  matching: find.byType(TextField),
);

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<void> pumpSearch(
    WidgetTester tester,
    String query, {
    _FakeInkSearch? slot,
  }) async {
    await tester.runAsync(() => seedSampleLibrary(backend));
    final h = LibraryTestHarness(
      backend,
      extraOverrides: [
        if (slot != null) libraryInkSearchProvider.overrideWithValue(slot),
      ],
    );
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.enterText(_searchInput, query);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Finder hintText(String text) => find.descendant(
    of: find.byKey(InkSearchHintKeys.hint),
    matching: find.text(text),
  );

  testWidgets('no slot → no hint', (tester) async {
    await pumpSearch(tester, '없는검색어');
    expect(find.text(LibraryStrings.emptySearch('없는검색어')), findsOneWidget);
    expect(find.byKey(InkSearchHintKeys.hint), findsNothing);
  });

  testWidgets('ready → no hint; opening the search tells the slot', (
    tester,
  ) async {
    final slot = _FakeInkSearch(const LibraryInkSearchState());
    await pumpSearch(tester, '없는검색어', slot: slot);
    expect(find.byKey(InkSearchHintKeys.hint), findsNothing);
    expect(slot.calls, contains('opened'));
  });

  testWidgets('auto indexing off: the line in the empty state, [켜기]', (
    tester,
  ) async {
    final slot = _FakeInkSearch(
      const LibraryInkSearchState(phase: LibraryInkSearchPhase.autoIndexOff),
    );
    await pumpSearch(tester, '없는검색어', slot: slot);
    expect(find.text(LibraryStrings.emptySearch('없는검색어')), findsOneWidget);
    expect(hintText(LibraryStrings.inkAutoIndexOff), findsOneWidget);
    await tester.tap(find.byKey(InkSearchHintKeys.action));
    await tester.pump();
    expect(slot.calls, contains('turnOn'));
    expect(find.text(LibraryStrings.inkTurnOn), findsOneWidget);
  });

  testWidgets('above the results too; indexing shows the pages left without '
      'an action; ready hides it', (tester) async {
    final slot = _FakeInkSearch(
      const LibraryInkSearchState(
        phase: LibraryInkSearchPhase.indexing,
        remainingPages: 3,
      ),
    );
    await pumpSearch(tester, '수학', slot: slot);
    expect(find.byType(SearchResultsView), findsOneWidget);
    expect(hintText('손글씨를 읽는 중이에요 (3쪽 남음)'), findsOneWidget);
    expect(find.byKey(InkSearchHintKeys.action), findsNothing);

    slot.value = const LibraryInkSearchState();
    await tester.pump();
    expect(find.byKey(InkSearchHintKeys.hint), findsNothing);
  });

  testWidgets('model missing: [지금 받기] downloads (Wi-Fi only setting)', (
    tester,
  ) async {
    final slot = _FakeInkSearch(
      const LibraryInkSearchState(phase: LibraryInkSearchPhase.modelMissing),
    );
    await pumpSearch(tester, '없는검색어', slot: slot);
    expect(hintText(LibraryStrings.inkModelMissing), findsOneWidget);
    await tester.tap(find.byKey(InkSearchHintKeys.action));
    await tester.pump();
    expect(slot.calls, contains('download(cellular: false)'));
  });

  testWidgets('waiting for Wi-Fi: [지금 받기] twice — the cellular warning '
      'first, then a cellular download', (tester) async {
    final slot = _FakeInkSearch(
      const LibraryInkSearchState(phase: LibraryInkSearchPhase.waitingForWifi),
    );
    await pumpSearch(tester, '없는검색어', slot: slot);
    expect(hintText(LibraryStrings.inkWaitingForWifi), findsOneWidget);
    await tester.tap(find.byKey(InkSearchHintKeys.action));
    await tester.pump();
    expect(hintText(LibraryStrings.inkCellularConfirm), findsOneWidget);
    expect(slot.calls.where((c) => c.startsWith('download')), isEmpty);
    await tester.tap(find.byKey(InkSearchHintKeys.action));
    await tester.pump();
    expect(slot.calls, contains('download(cellular: true)'));
    expect(hintText(LibraryStrings.inkWaitingForWifi), findsOneWidget);
  });

  testWidgets('downloading: the state, no action', (tester) async {
    final slot = _FakeInkSearch(
      const LibraryInkSearchState(
        phase: LibraryInkSearchPhase.modelDownloading,
      ),
    );
    await pumpSearch(tester, '없는검색어', slot: slot);
    expect(hintText(LibraryStrings.inkModelDownloading), findsOneWidget);
    expect(find.byKey(InkSearchHintKeys.action), findsNothing);
  });

  testWidgets('waiting for Wi-Fi does not claim there is no Wi-Fi', (
    tester,
  ) async {
    expect(LibraryStrings.inkWaitingForWifi, isNot(contains('연결되면')));
    expect(LibraryStrings.inkWaitingForWifi, contains('받는 중'));
    expect(LibraryStrings.inkWaitingForWifi, isNot(contains('와이파이')));
  });

  testWidgets('unsupported: the reason, no action', (tester) async {
    final slot = _FakeInkSearch(
      const LibraryInkSearchState(phase: LibraryInkSearchPhase.unsupported),
    );
    await pumpSearch(tester, '없는검색어', slot: slot);
    expect(hintText(LibraryStrings.inkUnsupported), findsOneWidget);
    expect(find.byKey(InkSearchHintKeys.action), findsNothing);
  });

  testWidgets('indexing with the pages still being counted: no count', (
    tester,
  ) async {
    final slot = _FakeInkSearch(
      const LibraryInkSearchState(phase: LibraryInkSearchPhase.indexing),
    );
    await pumpSearch(tester, '없는검색어', slot: slot);
    expect(hintText('손글씨를 읽는 중이에요'), findsOneWidget);
  });

  testWidgets('focusing the search field tells the slot before any query', (
    tester,
  ) async {
    await tester.runAsync(() => seedSampleLibrary(backend));
    final slot = _FakeInkSearch(const LibraryInkSearchState());
    final h = LibraryTestHarness(
      backend,
      extraOverrides: [libraryInkSearchProvider.overrideWithValue(slot)],
    );
    await h.pump(tester);
    await tester.pumpAndSettle();
    expect(slot.calls, isEmpty);
    await tester.tap(_searchInput);
    await tester.pump();
    expect(slot.calls, ['opened']);
  });
}
