// PDF init_test (06-pdf 4.1, 6.16; 8 T0 B4 version, extended by T17 — contract 00-overview
// 7.6 B4 v1.2, PDF-2-2): a ProviderContainer that holds ONLY pdfIoOverrides() — no other
// override, not even core.noteStoreProvider — reads ink.pageBackgroundBuildersProvider =
// [PdfBackgroundLayerBuilder, TemplateBackgroundLayerBuilder()] without an exception and
// (2차 v2, m5-7/06-pdf 4.1.2 — C2-20: now [PdfBackgroundLayerBuilder, ...INK's
// defaultPageBackgroundBuilders] = [pdf, image, template]; unit/init_v2_test.dart has 6.3 ①~④)
// without building the render chain (INK controllers / thumbnail renderer, INFRA
// pdf_module_test). Since PDF T9 the first entry is the renderer-backed builder
// (isPaperOnly == false); the paperOnly group uses the placeholder directly.
// pdfRenderStatsProvider has its T8 body: with core.noteStoreProvider (fake) added it
// reads zero (PDF-4-2). T17: initializePdfIo keeps its config (pdfIoConfigProvider's
// default), sets the pdfrx wasm module URL, warms the engine up without awaiting it (a
// failure throws nothing), is idempotent (a different config asserts) and registers the
// PDFium licenses once.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/init.dart' show PdfIoRuntime;
import 'package:pdf_io/src/licenses.dart';
import 'package:pdf_io/testing.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

const String _assetId =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

ink.InkBackgroundSpec _pdfSpec({int paper = core.PaperColors.white}) =>
    ink.InkBackgroundSpec(
      kind: ink.InkBackgroundKind.pdf,
      paperColorArgb: paper,
      assetId: _assetId,
      pdfPageIndex: 0,
    );

/// Counts provider creations by name.
final class _Builds extends ProviderObserver {
  final Map<String, int> counts = {};

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    final name = context.provider.name;
    if (name != null) counts[name] = (counts[name] ?? 0) + 1;
  }
}

/// An engine whose initialization waits for [done].
final class _SlowEngine implements PdfEngine {
  final Completer<void> done = Completer<void>();
  int calls = 0;

  @override
  Future<void> ensureInitialized() {
    calls++;
    return done.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Serves every license asset as 'license text of {file}' (missing → null) through the
/// asset channel rootBundle reads.
void _serveLicenses({Set<String> missing = const {}}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler('flutter/assets', (message) async {
    final key = utf8.decode(
      message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes),
    );
    if (!key.startsWith(pdfiumLicenseAssetDir)) return null;
    final file = key.substring(pdfiumLicenseAssetDir.length);
    if (missing.contains(file)) return null;
    return ByteData.sublistView(utf8.encode('license text of $file'));
  });
  addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;

  setUp(() => container = ProviderContainer(overrides: pdfIoOverrides()));
  tearDown(() => container.dispose());

  test('pdfIoOverrides() = config + INK builder list (always both)', () {
    expect(pdfIoOverrides(), hasLength(2));
    expect(pdfIoOverrides(config: const PdfIoConfig()), hasLength(2));
  });

  test('builders read without an exception', () {
    final builders = container.read(ink.pageBackgroundBuildersProvider);
    // 2차 v2: PDF first, then INK's default list (image, template).
    expect(builders, hasLength(3));
    final first = builders[0];
    expect(first, isA<PdfBackgroundLayerBuilder>());
    expect((first as PdfBackgroundLayerBuilder).isPaperOnly, isFalse);
    expect(builders[1], isA<ink.ImageBackgroundLayerBuilder>());
    expect(builders[2], isA<ink.TemplateBackgroundLayerBuilder>());
    expect(
      identical(first, container.read(pdfBackgroundLayerBuilderProvider)),
      isTrue,
    );
  });

  test('the builder read does not touch core.noteStoreProvider', () {
    final builders = container.read(ink.pageBackgroundBuildersProvider);
    expect(builders.first.handles(_pdfSpec()), isTrue);
    // The container really has no store: reading it fails, the read above did not.
    expect(() => container.read(core.noteStoreProvider), throwsA(anything));
  });

  test('pdfIoConfigProvider = the given config, else the default', () {
    expect(container.read(pdfIoConfigProvider), const PdfIoConfig());
    const config = PdfIoConfig(warmUpOnStart: false);
    final custom = ProviderContainer(overrides: pdfIoOverrides(config: config));
    addTearDown(custom.dispose);
    expect(custom.read(pdfIoConfigProvider), config);
  });

  test('INK readers of the builder list work in this container', () {
    expect(
      container.read(ink.inkPageThumbnailRendererProvider),
      isA<core.PageThumbnailRenderer>(),
    );
  });

  test('other B4 state providers read their idle values', () {
    expect(container.read(pdfActiveSearchProvider), PdfSearchState.idle);
    expect(
      container.read(pdfSearchHighlightsProvider).value,
      PdfSearchState.idle,
    );
    expect(
      container.read(pdfImportJobProvider),
      const PdfJobIdle<PdfImportResult>(),
    );
    expect(
      container.read(pdfExportJobProvider),
      const PdfJobIdle<PdfExportResult>(),
    );
    expect(container.read(pdfBatchExportJobProvider), const PdfBatchJobIdle());
  });

  test('reading the builder list builds no renderer, pool or gateway', () {
    final builds = _Builds();
    final observed = ProviderContainer(
      overrides: pdfIoOverrides(),
      observers: [builds],
    );
    addTearDown(observed.dispose);
    expect(observed.read(ink.pageBackgroundBuildersProvider), hasLength(3));
    expect(builds.counts.keys, contains('pdfBackgroundLayerBuilderProvider'));
    for (final name in [
      'pdfPageRendererProvider',
      'pdfDocumentPoolProvider',
      'pdfNoteGatewayProvider',
      'pdfEngineProvider',
    ]) {
      expect(builds.counts.containsKey(name), isFalse, reason: name);
    }
  });

  test('pdfRenderStatsProvider with a fake store added: zero', () {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final withStore = ProviderContainer(
      overrides: [
        ...pdfIoOverrides(),
        core.noteStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(withStore.dispose);
    expect(withStore.read(pdfRenderStatsProvider).value, PdfRenderStats.zero);
  });

  group('initializePdfIo (T17)', () {
    setUp(() {
      PdfIoRuntime.debugReset();
      LicenseRegistry.reset();
      rootBundle.clear(); // loadString caches per key
    });
    tearDown(() {
      PdfIoRuntime.debugReset();
      LicenseRegistry.reset();
    });

    test(
      'keeps its config: provider default, pdfIoOverrides(), pdfrx URL',
      () async {
        const config = PdfIoConfig(
          pdfiumWasmModulesUrl: 'https://cdn.example.test/pdfium/',
          warmUpOnStart: false,
          limits: PdfImportLimits(maxBytes: 10 * 1024 * 1024),
        );
        expect(PdfIoRuntime.isInitialized, isFalse);
        await initializePdfIo(config: config);
        expect(PdfIoRuntime.isInitialized, isTrue);
        expect(PdfIoRuntime.config, config);
        expect(
          rx.Pdfrx.pdfiumWasmModulesUrl,
          'https://cdn.example.test/pdfium/',
        );

        final plain = ProviderContainer();
        addTearDown(plain.dispose);
        expect(plain.read(pdfIoConfigProvider), config);
        final overridden = ProviderContainer(overrides: pdfIoOverrides());
        addTearDown(overridden.dispose);
        expect(overridden.read(pdfIoConfigProvider), config);
        expect(pdfIoOverrides(), hasLength(2));
        // The error texts read the limits of this config ({max}).
        expect(
          const PdfIoException(PdfErrorCode.tooLarge).userMessage,
          'PDF가 너무 커요. 최대 10MB까지 가져올 수 있어요.',
        );
      },
    );

    test(
      'idempotent; a different config asserts and the first stays',
      () async {
        const config = PdfIoConfig(warmUpOnStart: false);
        await initializePdfIo(config: config);
        await initializePdfIo(config: config); // same value: nothing
        await initializePdfIo(config: const PdfIoConfig(warmUpOnStart: false));
        await expectLater(
          initializePdfIo(
            config: const PdfIoConfig(
              warmUpOnStart: false,
              generateCoverThumbnail: false,
            ),
          ),
          throwsA(isA<AssertionError>()),
        );
        expect(PdfIoRuntime.config, config);
      },
    );

    test(
      'warm-up starts without being awaited; its failure throws nothing',
      () async {
        final slow = _SlowEngine();
        PdfIoRuntime.warmUpEngine = () => slow;
        await initializePdfIo(); // returns while the engine still initializes
        expect(slow.calls, 1);
        expect(slow.done.isCompleted, isFalse);
        slow.done.completeError(
          const PdfIoException(PdfErrorCode.engineUnavailable),
        );
        await pumpEventQueue(); // no unhandled error reaches the test zone

        PdfIoRuntime.debugReset();
        final failing = FakePdfEngine()
          ..initError = const PdfIoException(PdfErrorCode.engineUnavailable);
        PdfIoRuntime.warmUpEngine = () => failing;
        await initializePdfIo();
        await pumpEventQueue();
        expect(failing.ensureInitializedCalls, 1);

        PdfIoRuntime.debugReset();
        final idle = FakePdfEngine();
        PdfIoRuntime.warmUpEngine = () => idle;
        await initializePdfIo(config: const PdfIoConfig(warmUpOnStart: false));
        expect(idle.ensureInitializedCalls, 0);
      },
    );

    test('registers the PDFium licenses once; read only when listed', () async {
      _serveLicenses();
      await initializePdfIo(config: const PdfIoConfig(warmUpOnStart: false));
      await initializePdfIo(config: const PdfIoConfig(warmUpOnStart: false));
      final entries = await LicenseRegistry.licenses.toList();
      expect(entries, hasLength(pdfiumLicenseFiles.length));
      expect(pdfiumLicenseFiles, hasLength(20)); // 19 files (7.1) + LICENSE
      final pdfium = [
        for (final e in entries)
          if (e.packages.contains('PDFium')) e,
      ];
      expect(pdfium, hasLength(1));
      expect(
        pdfium.single.paragraphs.map((p) => p.text).join('\n'),
        'license text of pdfium.txt',
      );
      expect({
        for (final e in entries) ...e.packages,
      }, containsAll(['FreeType', 'ICU', 'libjpeg-turbo', 'pdfium-binaries']));
    });

    test('an unreadable license file is reported and left out', () async {
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      addTearDown(() => FlutterError.onError = previous);
      _serveLicenses(missing: {'icu.txt'});
      await initializePdfIo(config: const PdfIoConfig(warmUpOnStart: false));
      final entries = await LicenseRegistry.licenses.toList();
      expect(entries, hasLength(pdfiumLicenseFiles.length - 1));
      expect(entries.any((e) => e.packages.contains('ICU')), isFalse);
      expect(reports, hasLength(1));
      expect(reports.single.library, 'pdf_io');
    });
  });

  group('paperOnly builder', () {
    const builder = PdfBackgroundLayerBuilder.paperOnly();

    test('handles pdf backgrounds with an asset and a page index only', () {
      expect(builder.handles(_pdfSpec()), isTrue);
      expect(
        builder.handles(
          const ink.InkBackgroundSpec(
            kind: ink.InkBackgroundKind.pdf,
            pdfPageIndex: 0,
          ),
        ),
        isFalse,
      );
      expect(
        builder.handles(
          const ink.InkBackgroundSpec(
            kind: ink.InkBackgroundKind.pdf,
            assetId: _assetId,
          ),
        ),
        isFalse,
      );
      for (final kind in [
        ink.InkBackgroundKind.blank,
        ink.InkBackgroundKind.template,
        ink.InkBackgroundKind.image,
        ink.InkBackgroundKind.unknown,
      ]) {
        expect(
          builder.handles(
            ink.InkBackgroundSpec(
              kind: kind,
              assetId: _assetId,
              pdfPageIndex: 0,
            ),
          ),
          isFalse,
          reason: kind.name,
        );
      }
    });

    test('renderStill → null', () async {
      expect(
        await builder.renderStill(
          _pdfSpec(),
          pageSize: const Size(595, 842),
          pixelSize: const Size(119, 168),
        ),
        isNull,
      );
    });

    testWidgets(
      'build: opaque paper of pageSize × viewScale, no pointer handling',
      (tester) async {
        // Semi-transparent ivory: the paper must still be painted opaque.
        final ctx = ink.PageBackgroundContext(
          pageId: 'p1',
          pageSize: const Size(200, 100),
          background: _pdfSpec(paper: 0x80FBF7EC),
          viewScale: 1.5,
          ancestorScale:
              2, // never multiplied into the layout (contract 7.2.16 v1.1)
          devicePixelRatio: 2,
          isScaling: false,
        );
        const key = Key('background');
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: Builder(
                  builder: (context) => builder.build(context, ctx),
                ),
              ),
            ),
          ),
        );

        expect(tester.getSize(find.byKey(key)), const Size(300, 150));
        final ignore = tester.widget<IgnorePointer>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(IgnorePointer),
          ),
        );
        expect(ignore.ignoring, isTrue);

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final data = await image.toByteData();
            return (image.width, image.height, data!);
          } finally {
            image.dispose();
          }
        });
        final (width, height, data) = pixels!;
        expect((width, height), (300, 150));
        for (final (x, y) in [(0, 0), (150, 75), (299, 149), (299, 0)]) {
          final i = (y * width + x) * 4;
          expect(
            [
              data.getUint8(i),
              data.getUint8(i + 1),
              data.getUint8(i + 2),
              data.getUint8(i + 3),
            ],
            [0xFB, 0xF7, 0xEC, 0xFF],
            reason: 'pixel ($x, $y)',
          );
        }
      },
    );
  });
}
