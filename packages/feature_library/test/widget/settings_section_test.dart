// LibrarySettingsSection (05-library 4.5, 8 L18; contract 7.2.18 / 7.4.11):
// a body only (no Scaffold, no title); every change is stored at once in
// library.newNote.defaults as NewNoteOptions.toJson(); a value set on another
// device shows; a custom size out of range shows the error and is not
// stored; inputs are disabled while the settings load.
import 'dart:async';

import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/new_note_spec.dart';
import 'package:feature_library/src/model/page_size_mm.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/pump_library.dart';
import '../support/test_sizes.dart';

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  /// The section inside a settings-like frame (INFRA draws the Scaffold, the
  /// group header and the title, at most 720 wide).
  Future<void> pumpSection(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await pumpLibrary(
      tester,
      overrides: [...backend.overrides, ...overrides],
      size: TestSizes.ipad13Portrait,
      home: const Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(width: 720, child: LibrarySettingsSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<NewNoteOptions> stored(WidgetTester tester) async =>
      NewNoteOptions.fromJson(
        await real(
          tester,
          () => backend.store.settings.get(LibrarySettingsKeys.newNoteDefaults),
        ),
      );

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('a body only: no Scaffold, no title; the 3 pickers', (
    tester,
  ) async {
    await pumpSection(tester);
    final section = find.byType(LibrarySettingsSection);
    expect(
      find.descendant(of: section, matching: find.byType(Scaffold)),
      findsNothing,
    );
    expect(find.text('새 노트 기본값'), findsNothing);
    expect(find.text(LibraryStrings.fieldPageSize), findsOneWidget);
    expect(find.text(LibraryStrings.fieldTemplate), findsOneWidget);
    expect(find.text(LibraryStrings.fieldPaperColor), findsOneWidget);
    expect(find.text(LibraryStrings.fieldTitle), findsNothing);
    expect(find.text(LibraryStrings.fieldCover), findsNothing);
    expect(tester.getSize(section).width, 720);
  });

  testWidgets('every change is stored at once as toJson()', (tester) async {
    await pumpSection(tester);
    await tapVisible(tester, find.text(LibraryStrings.pageSizeLetter));
    await tapVisible(tester, find.text(LibraryStrings.landscape));
    await tapVisible(
      tester,
      find.text(LibraryStrings.templateName(PageTemplateKind.grid)),
    );
    await tapVisible(
      tester,
      find.byTooltip(LibraryStrings.paperColorName(PaperColors.ivory)),
    );
    const expected = NewNoteOptions(
      preset: PageSizePreset.letter,
      orientation: PageOrientationChoice.landscape,
      template: PageTemplateKind.grid,
      paperColorArgb: PaperColors.ivory,
    );
    final json = await real(
      tester,
      () => backend.store.settings.get(LibrarySettingsKeys.newNoteDefaults),
    );
    expect(json, expected.toJson());
    expect(await stored(tester), expected);

    // 빈 페이지 = no template.
    await tapVisible(tester, find.text(LibraryStrings.templateName(null)));
    expect((await stored(tester)).template, isNull);
  });

  testWidgets('a value from another device shows', (tester) async {
    await pumpSection(tester);
    const other = NewNoteOptions(
      preset: PageSizePreset.widescreen16x9,
      orientation: PageOrientationChoice.landscape,
      template: PageTemplateKind.dotted,
    );
    await real(
      tester,
      () => backend.store.settings.set(
        LibrarySettingsKeys.newNoteDefaults,
        other.toJson(),
      ),
    );
    await tester.pumpAndSettle();
    final size = tester.widget<SegmentedButton<Object>>(
      find.byWidgetPredicate(
        (w) =>
            w is SegmentedButton &&
            w.segments.length == 4, // A4 · Letter · 16:9 · 사용자 지정
      ),
    );
    expect(size.selected, hasLength(1));
    expect(
      find.descendant(
        of: find.byWidget(size),
        matching: find.text(LibraryStrings.pageSize16x9),
      ),
      findsOneWidget,
    );
    final orientation = tester.widget<SegmentedButton<PageOrientationChoice>>(
      find.byType(SegmentedButton<PageOrientationChoice>),
    );
    expect(orientation.selected, {PageOrientationChoice.landscape});

    // The next local change builds on the other device's value.
    await tapVisible(
      tester,
      find.byTooltip(LibraryStrings.paperColorName(PaperColors.gray)),
    );
    expect(
      await stored(tester),
      other.copyWith(paperColorArgb: PaperColors.gray),
    );
  });

  testWidgets('custom size: out of range → error, not stored; 35.3 stored', (
    tester,
  ) async {
    await pumpSection(tester);
    await tapVisible(tester, find.text(LibraryStrings.pageSizeCustom));
    expect((await stored(tester)).isCustom, isTrue);
    final width = find.widgetWithText(TextField, LibraryStrings.customWidth);
    final rangeError = find.text(
      LibraryStrings.customSizeRange(
        PageSizeMm.minInputMm,
        PageSizeMm.maxInputMm,
      ),
    );
    await tester.enterText(width, '35.2');
    await tester.pump();
    expect(rangeError, findsOneWidget);
    await tester.pumpAndSettle();
    expect((await stored(tester)).customWidthMm, 210.0);

    await tester.enterText(width, '35.3');
    await tester.pump();
    expect(rangeError, findsNothing);
    await tester.pumpAndSettle();
    expect((await stored(tester)).customWidthMm, 35.3);
  });

  testWidgets('while the settings load: the defaults, inputs disabled', (
    tester,
  ) async {
    final never = StreamController<SettingsSnapshot>();
    addTearDown(never.close);
    await pumpSection(
      tester,
      overrides: [settingsSnapshotProvider.overrideWith((ref) => never.stream)],
    );
    final ignoring = tester.widget<IgnorePointer>(
      find
          .descendant(
            of: find.byType(LibrarySettingsSection),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(ignoring.ignoring, isTrue);
    await tester.tap(
      find.byTooltip(LibraryStrings.paperColorName(PaperColors.ivory)),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(await stored(tester), const NewNoteOptions());
    expect(backend.calls, isEmpty);
  });
}
