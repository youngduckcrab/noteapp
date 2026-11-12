// pdf_wiring.dart (docs/plans/01-infra.md 4.5.9, 6.8, 9.1; contract 7.2.17
// v1.1 'INFRA(전달만)', 7.3.3): menu mapping, PdfRenderStatsLines (≤ 4 Hz,
// fake_async), formatPdfRenderStats, and pdfRenderStatsSection on the REAL
// pdfRenderStatsProvider (B4 zero stats, C12-06).
import 'package:fake_async/fake_async.dart';
import 'package:feature_editor/feature_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/modules/pdf_wiring.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:pdf_io/pdf_io.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_native_paths.dart';
import '../fakes/fake_note_store_opener.dart';
import '../fakes/fake_pdf_actions.dart';
import '../fakes/fake_web_platform.dart';

final _section = Provider<DevOverlaySection>(
  pdfRenderStatsSection,
  name: '_pdfRenderStatsSectionTest',
);

/// A stats notifier that counts its listeners.
/// Stands in for PDF's export diagnostics behind pdfDevOverlayLinesProvider
/// (PdfExportDiagnostics is internal to pdf_io).
final class _ExportLines extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void set(List<String> lines) => state = lines;
}

final _exportLines = NotifierProvider<_ExportLines, List<String>>(
  _ExportLines.new,
  name: '_exportLines',
);

const _twoExportLines = [
  'export: peak 3.2 / 16.0 MB · copy 1.1 MB',
  'export: over budget 0 (total 0 in 1)',
];

final class _Stats extends ValueNotifier<PdfRenderStats> {
  _Stats() : super(PdfRenderStats.zero);

  int listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }
}

PdfRenderStats _stats({
  int previewBytes = 0,
  int tileBytes = 0,
  int thumbnailBytes = 0,
  int liveImages = 0,
  int queued = 0,
  int inflight = 0,
  int rendered = 0,
  int cancelled = 0,
  double lastRenderMs = 0,
  double p95RenderMs = 0,
  int openDocuments = 0,
  int overBudgetBytes = 0,
}) => PdfRenderStats(
  previewBytes: previewBytes,
  tileBytes: tileBytes,
  thumbnailBytes: thumbnailBytes,
  liveImages: liveImages,
  queued: queued,
  inflight: inflight,
  rendered: rendered,
  cancelled: cancelled,
  lastRenderMs: lastRenderMs,
  p95RenderMs: p95RenderMs,
  openDocuments: openDocuments,
  overBudgetBytes: overBudgetBytes,
);

const int _mib = 1024 * 1024;

EditorMenuContext _menu(List<(String, Rect?)> navigations) => EditorMenuContext(
  noteId: 'n1',
  pageIds: const ['p1', 'p2', 'p3'],
  currentPageIndex: 1,
  selectedPageIds: const ['p1', 'p3'],
  navigateToPage: (pageId, rect) => navigations.add((pageId, rect)),
);

void main() {
  group('pdfMenuInvocationOf', () {
    test('maps the four fields; onNavigate is navigateToPage itself — the '
        'focus rect arrives unchanged', () {
      final navigations = <(String, Rect?)>[];
      final menu = _menu(navigations);
      final invocation = pdfMenuInvocationOf(menu);
      expect(invocation.noteId, 'n1');
      expect(invocation.currentPageId, 'p2');
      expect(invocation.selectedPageIds, ['p1', 'p3']);
      expect(invocation.onNavigate, same(menu.navigateToPage));

      const rect = Rect.fromLTWH(10, 20, 30, 40);
      invocation.onNavigate!('p2', rect);
      invocation.onNavigate!('p3', null);
      expect(navigations, [('p2', rect), ('p3', null)]);
      expect(identical(navigations.first.$2, rect), isTrue);
    });

    test('an index outside the pages gives no current page', () {
      final invocation = pdfMenuInvocationOf(
        EditorMenuContext(
          noteId: 'n1',
          pageIds: const [],
          currentPageIndex: 0,
          navigateToPage: (_, _) {},
        ),
      );
      expect(invocation.currentPageId, isNull);
      expect(invocation.selectedPageIds, isEmpty);
    });
  });

  group('editorMenuItemFromPdf', () {
    testWidgets('same id / label / icon; onSelected runs the action with the '
        'mapped invocation', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final pdf = FakePdfActions();
      final action = pdf.action('pdf.export');
      final item = editorMenuItemFromPdf(action);
      expect(item.id, action.id);
      expect(item.label, action.label);
      expect(item.icon, action.icon);
      expect(item.isEnabled, isNull);

      final navigations = <(String, Rect?)>[];
      final menu = _menu(navigations);
      await item.onSelected(context, menu);
      final run = pdf.runs.single;
      expect(run.actionId, 'pdf.export');
      expect(run.context, same(context));
      expect(run.invocation.noteId, 'n1');
      expect(run.invocation.currentPageId, 'p2');
      expect(run.invocation.selectedPageIds, ['p1', 'p3']);
      expect(run.invocation.onNavigate, same(menu.navigateToPage));
    });

    test('isEnabled is converted when the action has one', () {
      final pdf = FakePdfActions();
      final item = editorMenuItemFromPdf(
        pdf.action('pdf.search', withIsEnabled: true),
      );
      expect(item.isEnabled, isNotNull);
      expect(item.isEnabled!(_menu([])), isTrue);
      expect(
        item.isEnabled!(
          EditorMenuContext(
            noteId: 'n2',
            pageIds: const ['a'],
            currentPageIndex: 0,
            navigateToPage: (_, _) {},
          ),
        ),
        isFalse,
      );
      expect(pdf.enabledChecks.map((c) => (c.$1, c.$2.noteId)), [
        ('pdf.search', 'n1'),
        ('pdf.search', 'n2'),
      ]);
    });

    test('editorExtensionsFromPdf keeps both lists in order, no app bar '
        'trailing', () {
      final pdf = FakePdfActions();
      final extensions = editorExtensionsFromPdf(
        moreMenu: [pdf.action('b'), pdf.action('a'), pdf.action('c')],
        addPageSources: [pdf.action('pdf.insert')],
      );
      expect(extensions.moreMenuItems.map((i) => i.id), ['b', 'a', 'c']);
      expect(extensions.addPageSources.map((i) => i.id), ['pdf.insert']);
      expect(extensions.appBarTrailing, isNull);
      final empty = editorExtensionsFromPdf(moreMenu: [], addPageSources: []);
      expect(empty.moreMenuItems, isEmpty);
      expect(empty.addPageSources, isEmpty);
    });
  });

  group('formatPdfRenderStats', () {
    test('the 6.8 example', () {
      final lines = formatPdfRenderStats(
        _stats(
          previewBytes: (12.3 * _mib).round(),
          tileBytes: (40.1 * _mib).round(),
          thumbnailBytes: 2 * _mib,
          queued: 3,
          inflight: 1,
          rendered: 120,
          cancelled: 4,
          liveImages: 18,
          lastRenderMs: 12.4,
          p95RenderMs: 30,
          openDocuments: 2,
        ),
      );
      expect(lines, [
        '메모리 미리보기 12.3 · 타일 40.1 · 썸네일 2.0 MB (초과 0 MB)',
        '대기 3 · 진행 1 · 완료 120 · 취소 4 · 이미지 18',
        '렌더 최근 12ms · p95 30ms · 열린 문서 2',
      ]);
    });

    test('zero stats and an over-budget value', () {
      expect(formatPdfRenderStats(PdfRenderStats.zero), [
        '메모리 미리보기 0 · 타일 0 · 썸네일 0 MB (초과 0 MB)',
        '대기 0 · 진행 0 · 완료 0 · 취소 0 · 이미지 0',
        '렌더 최근 0ms · p95 0ms · 열린 문서 0',
      ]);
      expect(
        formatPdfRenderStats(_stats(overBudgetBytes: 3 * _mib ~/ 2)).first,
        '메모리 미리보기 0 · 타일 0 · 썸네일 0 MB (초과 1.5 MB)',
      );
    });
  });

  group('PdfRenderStatsLines', () {
    test('starts from the current stats', () {
      final stats = _Stats()..value = _stats(queued: 7);
      final lines = PdfRenderStatsLines(stats);
      expect(lines.value, formatPdfRenderStats(_stats(queued: 7)));
      expect(stats.listeners, 1);
      lines.dispose();
    });

    test('100 changes in one second → at most 4 updates, the last value '
        'wins', () {
      fakeAsync((async) {
        final stats = _Stats();
        final lines = PdfRenderStatsLines(stats);
        var updates = 0;
        lines.addListener(() => updates++);
        for (var i = 1; i <= 100; i++) {
          stats.value = _stats(rendered: i);
          async.elapse(const Duration(milliseconds: 10));
        }
        expect(updates, lessThanOrEqualTo(4));
        expect(updates, greaterThan(0));
        async.elapse(const Duration(milliseconds: 250));
        expect(lines.value, formatPdfRenderStats(_stats(rendered: 100)));
        final settled = updates;
        async.elapse(const Duration(seconds: 1));
        expect(updates, settled);
        lines.dispose();
      });
    });

    test('a change back to the shown lines does not notify', () {
      fakeAsync((async) {
        final stats = _Stats();
        final lines = PdfRenderStatsLines(stats);
        var updates = 0;
        lines.addListener(() => updates++);
        stats.value = _stats(queued: 1);
        stats.value = PdfRenderStats.zero;
        async.elapse(const Duration(milliseconds: 250));
        expect(updates, 0);
        lines.dispose();
      });
    });

    test(
      '(C26-02) the export lines follow the render lines; a change of '
      'them is throttled the same way; dispose removes that listener too',
      () {
        fakeAsync((async) {
          final stats = _Stats()..value = _stats(queued: 1);
          final export = ValueNotifier<List<String>>(const []);
          final lines = PdfRenderStatsLines(stats, exportLines: export);
          expect(lines.value, formatPdfRenderStats(_stats(queued: 1)));
          var updates = 0;
          lines.addListener(() => updates++);
          export.value = _twoExportLines;
          expect(updates, 0);
          async.elapse(const Duration(milliseconds: 250));
          expect(updates, 1);
          expect(lines.value, [
            ...formatPdfRenderStats(_stats(queued: 1)),
            ..._twoExportLines,
          ]);
          lines.dispose();
          export.value = const [];
          async.elapse(const Duration(seconds: 1));
          expect(updates, 1);
          expect(async.pendingTimers, isEmpty);
          export.dispose();
        });
      },
    );

    test('dispose removes the stats listener and cancels the timer', () {
      fakeAsync((async) {
        final stats = _Stats();
        final lines = PdfRenderStatsLines(stats);
        stats.value = _stats(queued: 2);
        expect(async.pendingTimers, hasLength(1));
        lines.dispose();
        expect(stats.listeners, 0);
        expect(async.pendingTimers, isEmpty);
        stats.value = _stats(queued: 3);
        async.elapse(const Duration(seconds: 1));
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('pdfRenderStatsSection on the real pdfRenderStatsProvider', () {
    Future<ProviderContainer> moduleOnlyContainer({
      List<Override> extra = const [],
    }) async {
      final web = FakeWebPlatform();
      final store = CountingNoteStore();
      addTearDown(store.inner.close);
      final bootstrapper = AppBootstrapper(
        modules: [
          CoreModule(
            nativePaths: noNativePaths,
            open: fakeOpenNoteStore(store: store).call,
          ),
          PdfModule(),
          FeatureWiringModule(),
        ],
        buildInfo: BuildInfo.local,
        runtimeInfo: RuntimeInfo.detect(web),
        web: web,
        errorLog: AppErrorLog(),
        ownerId: kLocalOwnerId,
      );
      addTearDown(bootstrapper.shutdown);
      final success = await bootstrapper.run() as BootstrapSuccess;
      // ProviderContainer (not .test): the test disposes it itself.
      return ProviderContainer(overrides: [...success.overrides, ...extra]);
    }

    test('id, title, three lines = the B4 zero stats; the lines are '
        'disposed with the container', () async {
      final container = await moduleOnlyContainer();
      final section = container.read(_section);
      expect(section.id, 'pdf.render');
      expect(section.title, 'PDF 렌더');
      final lines = section.lines;
      expect(lines.value, hasLength(3));
      expect(lines.value, formatPdfRenderStats(PdfRenderStats.zero));
      expect(lines, isA<PdfRenderStatsLines>());

      container.dispose();
      expect(
        () => (lines as PdfRenderStatsLines).addListener(() {}),
        throwsA(isA<FlutterError>()),
      );
    });

    test('(contract v2.6 C26-02) pdfDevOverlayLinesProvider: empty before '
        'the first export (three lines), its two export lines appended after '
        'one, the notifier disposed with the container', () async {
      // Real time: Riverpod schedules the dependents' refresh outside a
      // fake-async zone. Polled, nothing about durations is asserted.
      final container = await moduleOnlyContainer(
        extra: [
          pdfDevOverlayLinesProvider.overrideWith(
            (ref) => ref.watch(_exportLines),
          ),
        ],
      );
      // Listened, as the developer overlay watches its sections (an
      // unlistened provider is paused in Riverpod 3).
      final lines = container.listen(_section, (_, _) {}).read().lines;
      expect(lines.value, formatPdfRenderStats(PdfRenderStats.zero));
      container.read(_exportLines.notifier).set(_twoExportLines);
      for (var i = 0; i < 100 && lines.value.length < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(lines.value, [
        ...formatPdfRenderStats(PdfRenderStats.zero),
        ..._twoExportLines,
      ]);
      container.dispose();
      expect(
        () => (lines as PdfRenderStatsLines).addListener(() {}),
        throwsA(isA<FlutterError>()),
      );
    });
  });
}
