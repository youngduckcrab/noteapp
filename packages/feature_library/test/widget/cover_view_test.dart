// NoteCoverView (05-library 6.15.1, 8 L11): a cached first page thumbnail →
// Image, nothing cached → placeholder, color card title / spine colors, a
// cache write updates the cover by itself, no renderer slot → placeholder
// only, a rebuild with a new firstPageId → one new request, asset covers.
import 'dart:typed_data' show Uint8List;

import 'package:feature_library/src/appearance/cover_palette.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/note_cover_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Page;
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/fake_library_backend.dart';
import '../support/fake_thumbnail_renderer.dart';
import '../support/pump_library.dart';
import '../support/recording_thumbnail_io.dart';

const double _width = 150, _height = 200;

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  /// Pumps one NoteCoverView for the note in [shown] (null = no cover).
  Future<ValueNotifier<Note?>> pumpCover(
    WidgetTester tester,
    Note note, {
    List<Override> overrides = const [],
    double width = _width,
    double height = _height,
  }) async {
    final shown = ValueNotifier<Note?>(note);
    addTearDown(shown.dispose);
    await pumpLibrary(
      tester,
      overrides: [...backend.overrides, ...overrides],
      home: Center(
        child: ValueListenableBuilder<Note?>(
          valueListenable: shown,
          builder: (_, n, _) => n == null
              ? const SizedBox()
              : NoteCoverView(note: n, width: width, height: height),
        ),
      ),
    );
    await tester.pump();
    return shown;
  }

  PageThumbnail thumbOf(Page page) => PageThumbnail(
    pageId: page.id,
    contentRevision: page.contentRevision,
    width: 1,
    height: 1,
    mimeType: 'image/png',
    bytes: kTestPng1x1,
  );

  Future<void> writeThumb(WidgetTester tester, Note note) =>
      real(tester, () async {
        final page = (await backend.store.content.getPage(note.firstPageId!))!;
        await backend.store.thumbnails.write(thumbOf(page));
      });

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(NoteCoverView)));

  testWidgets('a cached first page thumbnail → Image (contain, DPR width)', (
    tester,
  ) async {
    final n = await real(tester, () => backend.seedNote('n'));
    await writeThumb(tester, n);
    await pumpCover(tester, n);
    await tester.pump();
    expect(find.byType(CoverPlaceholder), findsNothing);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect(image.gaplessPlayback, isTrue);
    expect(image.filterQuality, FilterQuality.medium);
    // cacheWidth = (150 × DPR 2).round()
    expect((image.image as ResizeImage).width, 300);
    expect(tester.getSize(find.byType(NoteCoverView)), const Size(150, 200));
  });

  testWidgets('no thumbnail → placeholder', (tester) async {
    final n = await real(tester, () => backend.seedNote('n'));
    await pumpCover(tester, n);
    await tester.pump();
    expect(find.byType(CoverPlaceholder), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    // (UI stage 2) the 노트 line icon.
    expect(
      find.byWidgetPredicate((w) => w is AppIcon && w.kind == AppIconKind.note),
      findsOneWidget,
    );
    // No first page at all → placeholder too.
    final noPage = n.copyWith(clearFirstPageId: true);
    final shown = await pumpCover(tester, noPage);
    shown.value = noPage;
    await tester.pump();
    expect(find.byType(CoverPlaceholder), findsOneWidget);
  });

  testWidgets('a cache write updates the cover by itself', (tester) async {
    final n = await real(tester, () => backend.seedNote('n'));
    await pumpCover(tester, n);
    await tester.pump();
    expect(find.byType(CoverPlaceholder), findsOneWidget);
    await writeThumb(tester, n); // e.g. PDF import or the editor
    await tester.pump();
    await tester.pump();
    expect(find.byType(CoverPlaceholder), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('no renderer slot → placeholder only, nothing drawn or written', (
    tester,
  ) async {
    final n = await real(tester, () => backend.seedNote('n'));
    final reader = RecordingContentReader(backend.store.content);
    await pumpCover(
      tester,
      n,
      overrides: [noteContentReaderProvider.overrideWithValue(reader)],
    );
    final scheduler = containerOf(tester).read(coverThumbnailSchedulerProvider);
    expect(scheduler.isEnabled, isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(reader.log, isEmpty);
    expect(find.byType(CoverPlaceholder), findsOneWidget);
    expect(
      await real(tester, () => backend.store.thumbnails.read(n.firstPageId!)),
      isNull,
    );
  });

  testWidgets('with a renderer: placeholder, then the drawn first page', (
    tester,
  ) async {
    final n = await real(tester, () => backend.seedNote('n'));
    final renderer = FakeThumbnailRenderer();
    await pumpCover(
      tester,
      n,
      overrides: [pageThumbnailRendererProvider.overrideWithValue(renderer)],
    );
    await tester.pump(const Duration(milliseconds: 799));
    expect(renderer.rendered, isEmpty);
    expect(find.byType(CoverPlaceholder), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump();
    expect(renderer.rendered, [n.firstPageId]);
    expect(find.byType(CoverPlaceholder), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('rebuilt with a new firstPageId → one new request', (
    tester,
  ) async {
    final n = await real(
      tester,
      () => backend.seedNote(
        'n',
        pages: const [PageDraft.blankA4, PageDraft.blankA4],
      ),
    );
    final pages = await real(tester, () => backend.store.content.pagesOf(n.id));
    final p1 = pages[0].id, p2 = pages[1].id;
    final reader = RecordingContentReader(backend.store.content);
    final renderer = FakeThumbnailRenderer();
    final shown = await pumpCover(
      tester,
      n,
      overrides: [
        noteContentReaderProvider.overrideWithValue(reader),
        pageThumbnailRendererProvider.overrideWithValue(renderer),
      ],
    );
    await tester.pump(const Duration(seconds: 1));
    expect(reader.getPageCalls, ['getPage $p1']);
    // A rebuild with the same note value asks for nothing.
    shown.value = n.copyWith();
    await tester.pump(); // build (didUpdateWidget)
    await tester.pump(const Duration(seconds: 1));
    expect(reader.getPageCalls, ['getPage $p1']);
    // Pages reordered elsewhere: same updatedAt, new first page.
    shown.value = n.copyWith(firstPageId: p2);
    await tester.pump(); // build (didUpdateWidget → request)
    await tester.pump(const Duration(seconds: 1));
    expect(reader.getPageCalls, ['getPage $p1', 'getPage $p2']);
    expect(renderer.rendered, [p1, p2]);
    await tester.pump(const Duration(seconds: 1));
    expect(reader.getPageCalls, hasLength(2));
  });

  testWidgets('a cover removed before the start delay is not drawn', (
    tester,
  ) async {
    final n = await real(tester, () => backend.seedNote('n'));
    final renderer = FakeThumbnailRenderer();
    final shown = await pumpCover(
      tester,
      n,
      overrides: [pageThumbnailRendererProvider.overrideWithValue(renderer)],
    );
    final scheduler = containerOf(tester).read(coverThumbnailSchedulerProvider);
    expect(scheduler.pendingCount, 1);
    shown.value = null; // tile scrolled away
    await tester.pump();
    expect(scheduler.pendingCount, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(renderer.rendered, isEmpty);
  });

  testWidgets('color cover: title in coverForegroundFor, spine 20 % black', (
    tester,
  ) async {
    const dark = 0xFF2F4A7A, light = 0xFFF5F5F5;
    for (final (argb, expected) in [
      (dark, const Color(0xFFFFFFFF)),
      (light, const Color(0xDE000000)),
    ]) {
      final n = await real(
        tester,
        () => backend.seedNote('표지 $argb', cover: ColorCover(argb)),
      );
      await pumpCover(tester, n);
      final text = tester.widget<Text>(find.text('표지 $argb'));
      expect(text.style!.color, expected);
      expect(text.style!.fontSize, 16);
      expect(text.style!.fontWeight, FontWeight.w600);
      expect(text.maxLines, 2);
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == Color(argb),
        ),
        findsOneWidget,
      );
      final spine = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == coverSpineColorFor(argb),
      );
      expect(spine, findsOneWidget);
      expect(tester.getSize(spine), const Size(8, _height));
      // The title starts at 24 % of the height.
      expect(
        tester.getTopLeft(find.text('표지 $argb')).dy -
            tester.getTopLeft(find.byType(NoteCoverView)).dy,
        moreOrLessEquals(_height * 0.24),
      );
    }
    expect(
      coverSpineColorFor(0xFFFFFFFF),
      Color.lerp(const Color(0xFFFFFFFF), const Color(0xFF000000), 0.2),
    );
  });

  testWidgets('a narrow color cover (list row) shows no title', (tester) async {
    final n = await real(
      tester,
      () => backend.seedNote('목록', cover: ColorCover(CoverPalette.colors[1])),
    );
    await pumpCover(tester, n, width: 40, height: 52);
    expect(find.text('목록'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == Color(CoverPalette.colors[1]),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'asset cover: bytes → Image (cover); bytes missing → placeholder',
    (tester) async {
      final asset = await real(
        tester,
        () => backend.store.assets.put(
          kTestPng1x1,
          type: AssetType.image,
          mimeType: 'image/png',
        ),
      );
      final withBytes = await real(
        tester,
        () => backend.seedNote('그림', cover: AssetCover(asset.id)),
      );
      await pumpCover(tester, withBytes);
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect((image.image as ResizeImage).width, 300);
      expect(find.byType(CoverPlaceholder), findsNothing);

      final missing = await real(
        tester,
        () => backend.seedNote('없는 그림', cover: AssetCover('c' * 64)),
      );
      await pumpCover(tester, missing);
      await tester.pump();
      expect(find.byType(CoverPlaceholder), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('asset cover: the cover appears when the bytes arrive', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(kTestPng1x1);
    final id = (await real(
      tester,
      () => createFakeNoteStore().assets.put(
        bytes,
        type: AssetType.image,
        mimeType: 'image/png',
      ),
    )).id;
    final n = await real(
      tester,
      () => backend.seedNote('나중에 온 그림', cover: AssetCover(id)),
    );
    await pumpCover(tester, n);
    await tester.pump();
    expect(find.byType(CoverPlaceholder), findsOneWidget);
    await real(
      tester,
      () => backend.store.assets.put(
        bytes,
        type: AssetType.image,
        mimeType: 'image/png',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CoverPlaceholder), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
}
