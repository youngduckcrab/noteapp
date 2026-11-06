// AboutSection (docs/plans/01-infra.md 4.5.8, 9.1): shown values, diagnostics
// copy, license page, update check, and the backup flow — prepareBackup with
// a progress row → BackupReadySheet → deliverBackup → a snackbar per outcome;
// cancelling the wait (INFRA-3-3, 계약 7.2.9 v1.2) leaves no trace.
//
// The B2 fake store's exportBackupJson is UnimplementedError (계약 7.6):
// CountingNoteStore.exportBackupResult injects the bytes.
//
// 2차 J13 (docs/plans/m5-7/01-infra.md 6.12.3, 6.18): the Apple Pencil row
// over a PencilStylusExtrasSource on a fake pencil event stream.
// 2차 J14 (6.18): the feature row in four cases (all on · off in the build ·
// off in the developer menu · failed start) and in the diagnostics copy.
import 'dart:async';
import 'dart:convert';

import 'package:feature_editor/feature_editor.dart'
    show NoStylusExtras, stylusExtrasProvider;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/pencil/pencil_stylus_extras.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/settings/about_section.dart';
import 'package:noteapp/src/settings/backup_sheet.dart';
import 'package:noteapp/src/web/web_platform.dart';
import 'package:pencil_bridge/pencil_bridge.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_app_module.dart';
import '../fakes/fake_web_platform.dart';
import '../support/settings_harness.dart';

final Uint8List _bytes = Uint8List.fromList(utf8.encode('{"backup":true}'));

const Key _backupButton = Key('about-backup');
const Key _progress = Key('about-backup-progress');

Future<SettingsHarness> _pump(
  WidgetTester tester, {
  CountingNoteStore? store,
  FakeWebPlatform? web,
  BuildInfo build = testBuild,
  RuntimeInfo runtime = testRuntime,
  AppErrorLog? errorLog,
  List<Override> extra = const [],
}) async {
  final harness = SettingsHarness(
    store: store ?? CountingNoteStore(exportBackupResult: _bytes),
    web: web,
    build: build,
    runtime: runtime,
    errorLog: errorLog,
  );
  await harness.pump(tester, sectionPage(const AboutSection()), extra: extra);
  await tester.pump();
  return harness;
}

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key)).enabled;

/// Taps 백업 내보내기 and lets an ungated backup reach the sheet.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(_backupButton));
  await tester.pumpAndSettle();
  expect(find.byType(BackupReadySheet), findsOneWidget);
}

/// Records Clipboard.setData text.
List<String> _mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add(
          (call.arguments as Map<Object?, Object?>)['text']! as String,
        );
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  testWidgets('shows build, renderer, standalone, startup times and errors', (
    tester,
  ) async {
    final h = await _pump(tester);
    expect(find.text('0.1.0 (#42 · a1b2c3d · main)'), findsOneWidget);
    expect(find.text('CanvasKit (dart2js)'), findsOneWidget);
    expect(find.text(AppStrings.yes), findsOneWidget);
    expect(
      find.text(
        '페이지 열기→준비 1,850ms · 부트스트랩 1,300ms\n'
        'core 1,234ms · pdf 30ms (failedNonCritical)',
      ),
      findsOneWidget,
    );
    expect(find.text(AppStrings.none), findsOneWidget);

    // A record added from anywhere (even during a frame) is shown by a
    // rebuild scheduled after the next frame.
    h.errorLog.add(
      AppErrorRecord(
        time: DateTime(2026, 11, 4, 18, 20, 31),
        source: AppErrorSource.flutter,
        summary: 'RenderFlex overflowed',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('1건'), findsOneWidget);
    expect(
      find.text('18:20:31 flutter — RenderFlex overflowed'),
      findsOneWidget,
    );

    for (var i = 0; i < 7; i++) {
      h.errorLog.add(
        AppErrorRecord(
          time: DateTime(2026, 11, 4, 18, 21, i),
          source: AppErrorSource.module,
          summary: 'e$i',
          fatal: i == 6,
        ),
      );
    }
    await tester.pump();
    await tester.pump();
    expect(find.text('8건'), findsOneWidget);
    // The newest five, newest first.
    expect(find.text('18:21:06 module (fatal) — e6'), findsOneWidget);
    expect(find.text('18:21:02 module — e2'), findsOneWidget);
    expect(find.text('18:21:01 module — e1'), findsNothing);
    expect(
      tester.getTopLeft(find.text('18:21:06 module (fatal) — e6')).dy,
      lessThan(tester.getTopLeft(find.text('18:21:02 module — e2')).dy),
    );
  });

  testWidgets('off the web: 네이티브, not standalone', (tester) async {
    await _pump(
      tester,
      build: BuildInfo.local,
      runtime: const RuntimeInfo(
        isWeb: false,
        renderer: WebRenderer.notWeb,
        isStandalone: false,
      ),
    );
    expect(find.text(AppStrings.rendererNative), findsOneWidget);
    expect(find.text(AppStrings.no), findsOneWidget);
    expect(find.text('0.0.0 (#0 · local · local)'), findsOneWidget);
  });

  testWidgets('진단 정보 복사 → the DiagnosticReport text with the re-queried '
      'storage info, and a snackbar', (tester) async {
    final copied = _mockClipboard(tester);
    final store = CountingNoteStore(
      refreshResult: const StorageInfo(
        backend: StorageBackend.webOpfsShared,
        persistGranted: true,
      ),
    );
    await _pump(tester, store: store);
    await tester.pumpAndSettle();
    // The section keeps latestStorageInfoProvider alive (one refresh).
    expect(store.refreshCount, 1);

    await tester.tap(find.byKey(const Key('about-copy-diagnostics')));
    await tester.pump();
    expect(copied, hasLength(1));
    final text = copied.single;
    expect(text, startsWith('[필기노트 진단 정보] '));
    expect(text, contains('빌드: 0.1.0 (#42 · a1b2c3d · main) live'));
    expect(text, contains('실행: 웹 · CanvasKit (dart2js) · 홈 화면 앱: 예'));
    expect(text, contains('시작: 페이지 열기→준비 1,850ms / 부트스트랩 1,300ms'));
    expect(text, contains('저장소: webOpfsShared · 영구 보관 허용'));
    expect(text, contains('저장 상태: 대기 0건'));
    expect(text, contains('오류 없음'));
    expect(find.text(AppStrings.diagnosticsCopied), findsOneWidget);
  });

  testWidgets('오픈소스 라이선스 opens the license page', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('about-licenses')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LicensePage), findsOneWidget);
  });

  group('새 버전 확인', () {
    testWidgets('disabled for a local build (status text, button off)', (
      tester,
    ) async {
      await _pump(tester, build: BuildInfo.local);
      expect(find.text(AppStrings.updateDisabled), findsOneWidget);
      expect(_enabled(tester, const Key('about-check-update')), isFalse);
    });

    testWidgets('unknown → check → up to date / new version + 새로고침', (
      tester,
    ) async {
      final web = FakeWebPlatform(
        buildInfoJson: jsonEncode(testBuild.toJson()),
      );
      final module = FakeAppModule(id: 'core');
      final bootstrapper = AppBootstrapper(
        modules: [module],
        buildInfo: testBuild,
        runtimeInfo: testRuntime,
        web: web,
        errorLog: AppErrorLog(),
        ownerId: kLocalOwnerId,
      );
      await tester.runAsync(bootstrapper.run);
      await _pump(
        tester,
        web: web,
        extra: [appBootstrapperProvider.overrideWithValue(bootstrapper)],
      );
      expect(find.text(AppStrings.updateUnknown), findsOneWidget);

      await tester.tap(find.byKey(const Key('about-check-update')));
      await tester.pumpAndSettle();
      expect(web.fetchCount, 1);
      expect(find.textContaining('최신 버전이에요.'), findsOneWidget);
      expect(find.byKey(const Key('about-apply-update')), findsNothing);

      web.buildInfoJson = jsonEncode(
        const BuildInfo(
          version: '0.1.0',
          buildNumber: 43,
          gitSha: 'b2c3d4e5f60718293a4b5c6d7e8f9012345678a1',
          gitRef: 'main',
          channel: BuildChannel.live,
        ).toJson(),
      );
      await tester.tap(find.byKey(const Key('about-check-update')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.updateFound(43, 'b2c3d4e')), findsOneWidget);
      await tester.tap(find.byKey(const Key('about-apply-update')));
      await tester.pumpAndSettle();
      // applyUpdate: flush (notifyAppHidden) first, then reload.
      expect(module.hiddenCalls, 1);
      expect(web.reloadCount, 1);
    });
  });

  group('백업 내보내기', () {
    testWidgets('progress row while preparing (button disabled) → sheet', (
      tester,
    ) async {
      final gate = Completer<void>();
      final store = CountingNoteStore(
        flushGate: gate,
        exportBackupResult: _bytes,
      );
      await _pump(tester, store: store);
      expect(find.byKey(_progress), findsNothing);

      await tester.tap(find.byKey(_backupButton));
      await tester.pump();
      expect(find.byKey(_progress), findsOneWidget);
      expect(find.text(AppStrings.backupPreparing), findsOneWidget);
      expect(_enabled(tester, _backupButton), isFalse);
      expect(store.flushCount, 1);
      expect(find.text(AppStrings.backupSlowWrites), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_progress), findsNothing);
      expect(_enabled(tester, _backupButton), isTrue);
      expect(store.exportCount, 1);
      expect(find.byType(BackupReadySheet), findsOneWidget);
      expect(find.textContaining(RegExp(r'^noteapp-backup-')), findsOneWidget);
    });

    testWidgets('the share button only when canShareFiles', (tester) async {
      for (final canShare in [false, true]) {
        await _pump(
          tester,
          web: FakeWebPlatform(canShareFilesResult: canShare),
        );
        await _openSheet(tester);
        expect(
          find.text(AppStrings.backupShare),
          canShare ? findsOneWidget : findsNothing,
        );
        expect(find.text(AppStrings.backupDownload), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('each button → deliverBackup → its snackbar', (tester) async {
      final cases =
          <
            (
              String,
              FakeWebPlatform Function(),
              Key,
              String?,
              int,
              List<RecordedFile> Function(FakeWebPlatform),
            )
          >[
            (
              'download',
              FakeWebPlatform.new,
              const Key('backup-download'),
              AppStrings.backupDownloaded,
              0,
              (w) => w.downloads,
            ),
            (
              'download unsupported',
              () => FakeWebPlatform(downloadResult: false),
              const Key('backup-download'),
              AppStrings.backupUnsupported,
              0,
              (w) => w.downloads,
            ),
            (
              'share',
              () => FakeWebPlatform(canShareFilesResult: true),
              const Key('backup-share'),
              AppStrings.backupShared,
              0,
              (w) => w.shares,
            ),
            (
              'share cancelled',
              () => FakeWebPlatform(
                canShareFilesResult: true,
                shareResult: WebShareResult.cancelled,
              ),
              const Key('backup-share'),
              null,
              0,
              (w) => w.shares,
            ),
            (
              'share unsupported',
              () => FakeWebPlatform(
                canShareFilesResult: true,
                shareResult: WebShareResult.unsupported,
              ),
              const Key('backup-share'),
              AppStrings.backupUnsupported,
              0,
              (w) => w.shares,
            ),
            (
              'share failed',
              () => FakeWebPlatform(
                canShareFilesResult: true,
                shareResult: WebShareResult.failed,
              ),
              const Key('backup-share'),
              AppStrings.backupFailed,
              1,
              (w) => w.shares,
            ),
          ];
      for (final (name, makeWeb, button, message, records, calls) in cases) {
        final web = makeWeb();
        final h = await _pump(tester, web: web);
        await _openSheet(tester);
        await tester.tap(find.byKey(button));
        await tester.pumpAndSettle();
        expect(find.byType(BackupReadySheet), findsNothing, reason: name);
        final recorded = calls(web);
        expect(recorded, hasLength(1), reason: name);
        expect(recorded.single.bytes, same(_bytes), reason: name);
        expect(recorded.single.mimeType, 'application/json', reason: name);
        if (message == null) {
          expect(find.byType(SnackBar), findsNothing, reason: name);
        } else {
          expect(find.text(message), findsOneWidget, reason: name);
        }
        expect(h.errorLog.totalCount, records, reason: name);
        // Next case starts from a fresh tree (no snackbar carried over).
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('dismissing the sheet → no snackbar', (tester) async {
      final web = FakeWebPlatform();
      await _pump(tester, web: web);
      await _openSheet(tester);
      await tester.tapAt(const Offset(500, 40));
      await tester.pumpAndSettle();
      expect(find.byType(BackupReadySheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(web.downloads, isEmpty);
    });

    testWidgets('export error → failure snackbar + one record, no sheet', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        store: CountingNoteStore(exportBackupResult: StateError('broken')),
      );
      await tester.tap(find.byKey(_backupButton));
      await tester.pumpAndSettle();
      expect(find.byType(BackupReadySheet), findsNothing);
      expect(find.text(AppStrings.backupFailed), findsOneWidget);
      expect(h.errorLog.totalCount, 1);
      expect(h.errorLog.records.single.source, AppErrorSource.manual);
      expect(_enabled(tester, _backupButton), isTrue);
    });

    testWidgets('cancel while writes are retried: slow-write note, then no '
        'trace (INFRA-3-3)', (tester) async {
      // Never completes on its own: a commit that keeps being retried.
      final gate = Completer<void>();
      final store = CountingNoteStore(
        flushGate: gate,
        exportBackupResult: _bytes,
      );
      final h = await _pump(tester, store: store);
      final errorsBefore = h.errorLog.totalCount;

      await tester.tap(find.byKey(_backupButton));
      await tester.pump();
      expect(find.byKey(_progress), findsOneWidget);
      expect(find.byKey(const Key('about-backup-cancel')), findsOneWidget);
      expect(_enabled(tester, _backupButton), isFalse);

      store.emitStatus(
        const PersistenceStatus(
          pendingOps: 1,
          isWriting: true,
          consecutiveFailures: 3,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(AppStrings.backupSlowWrites), findsOneWidget);

      await tester.tap(find.byKey(const Key('about-backup-cancel')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(_progress), findsNothing);
      expect(find.text(AppStrings.backupSlowWrites), findsNothing);
      expect(_enabled(tester, _backupButton), isTrue);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(BackupReadySheet), findsNothing);
      expect(h.errorLog.totalCount, errorsBefore);

      // The abandoned wait ends later: still no sheet or snackbar.
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(BackupReadySheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(h.errorLog.totalCount, errorsBefore);
    });
  });

  group('Apple Pencil row (J13 — 6.12.3, 6.18)', () {
    const t = Duration(seconds: 3);
    late StreamController<PencilEvent> native;

    setUp(() {
      native = StreamController<PencilEvent>.broadcast();
    });
    tearDown(() => native.close());

    Finder pencilRow() => find.text(AppStrings.aboutPencil);

    /// Delivers the added events (a microtask), then builds the frame their
    /// `seen` change scheduled.
    Future<void> deliver(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    testWidgets('no row without a supported stylus source (web, Android)', (
      tester,
    ) async {
      await _pump(tester);
      expect(pencilRow(), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _pump(
        tester,
        extra: [stylusExtrasProvider.overrideWithValue(const NoStylusExtras())],
      );
      expect(pencilRow(), findsNothing);
    });

    testWidgets('iOS 17.5 · 더블탭 · 호버; squeeze and roll only after this '
        'run received one — the section listens itself while shown', (
      tester,
    ) async {
      final adapter = PencilStylusExtrasSource(
        capabilities: const PencilCapabilities(
          os: '17.5',
          squeeze: true,
          hover: true,
          roll: true,
        ),
        events: native.stream,
      );
      await _pump(
        tester,
        extra: [stylusExtrasProvider.overrideWithValue(adapter)],
      );
      expect(pencilRow(), findsOneWidget);
      expect(find.text('iOS 17.5 · 더블탭 · 호버'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('app.about.pencil')),
          matching: find.text('iOS 17.5 · 더블탭 · 호버'),
        ),
        findsOneWidget,
      );
      // Nothing else listens in this test: the section's own subscription.
      expect(native.hasListener, isTrue);

      native.add(const PencilTap(t, preferredAction: 'switchEraser'));
      await deliver(tester);
      expect(find.text('iOS 17.5 · 더블탭 · 호버'), findsOneWidget);

      native.add(
        const PencilSqueeze(t, phase: 'began', preferredAction: 'ignore'),
      );
      await deliver(tester);
      expect(find.text('iOS 17.5 · 더블탭 · 호버 · 스퀴즈(받음)'), findsOneWidget);

      native.add(const PencilRoll(t, angle: 0.5));
      await deliver(tester);
      expect(
        find.text('iOS 17.5 · 더블탭 · 호버 · 스퀴즈(받음) · 롤(받음)'),
        findsOneWidget,
      );

      // Leaving the section ends its subscription; what was seen stays.
      await tester.pumpWidget(const SizedBox());
      expect(native.hasListener, isFalse);
      expect(adapter.seen.value, (squeeze: true, roll: true));
    });

    testWidgets('seen before the section opened (the editor listened) shows '
        'at once', (tester) async {
      final adapter = PencilStylusExtrasSource(
        capabilities: const PencilCapabilities(os: '18.1', squeeze: true),
        events: native.stream,
      );
      final editor = adapter.events.listen((_) {});
      addTearDown(editor.cancel);
      native.add(
        const PencilSqueeze(t, phase: 'ended', preferredAction: 'ignore'),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      await _pump(
        tester,
        extra: [stylusExtrasProvider.overrideWithValue(adapter)],
      );
      expect(find.text('iOS 18.1 · 더블탭 · 스퀴즈(받음)'), findsOneWidget);
    });

    testWidgets('capabilities read failed → 능력을 읽지 못했어요 · 더블탭', (tester) async {
      await _pump(
        tester,
        extra: [
          stylusExtrasProvider.overrideWithValue(
            PencilStylusExtrasSource(
              capabilities: kPencilFallbackCapabilities,
              events: native.stream,
            ),
          ),
        ],
      );
      expect(find.text('능력을 읽지 못했어요 · 더블탭'), findsOneWidget);
    });

    testWidgets('landscape: the row fits', (tester) async {
      final h = SettingsHarness(
        store: CountingNoteStore(exportBackupResult: _bytes),
      );
      await h.pump(
        tester,
        sectionPage(const AboutSection()),
        logical: ipadLandscape,
        extra: [
          stylusExtrasProvider.overrideWithValue(
            PencilStylusExtrasSource(
              capabilities: const PencilCapabilities(os: '17.5', hover: true),
              events: native.stream,
            ),
          ),
        ],
      );
      await tester.pump();
      expect(find.text('iOS 17.5 · 더블탭 · 호버'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('feature row (J14 — 6.18)', () {
    const featureKey = ValueKey<String>('app.about.features');

    StartupReport report(List<(String, StartupStepOutcome)> steps) =>
        StartupReport(
          steps: [
            const StartupStep(
              id: 'core',
              elapsed: Duration(milliseconds: 120),
              outcome: StartupStepOutcome.ok,
            ),
            for (final (id, outcome) in steps)
              StartupStep(id: id, elapsed: Duration.zero, outcome: outcome),
          ],
          bootstrapElapsed: const Duration(milliseconds: 300),
        );

    Future<SettingsHarness> pumpFeatures(
      WidgetTester tester, {
      required AppFeatures compileTime,
      required AppFeatures started,
      required StartupReport report,
      Size logical = ipadPortrait,
    }) async {
      final h = SettingsHarness(
        store: CountingNoteStore(exportBackupResult: _bytes),
        report: report,
      );
      await h.pump(
        tester,
        sectionPage(AboutSection(compileTime: compileTime)),
        logical: logical,
        extra: [appFeaturesProvider.overrideWithValue(started)],
      );
      await tester.pump();
      return h;
    }

    String rowText(WidgetTester tester) {
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(featureKey),
          matching: find.byType(Text),
        ),
      );
      expect(texts.first.data, AppStrings.aboutFeatures);
      return texts.last.data!;
    }

    Color? rowColor(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(featureKey),
            matching: find.byType(Text),
          ),
        )
        .last
        .style
        ?.color;

    testWidgets('all on', (tester) async {
      await pumpFeatures(
        tester,
        compileTime: AppFeatures.all,
        started: AppFeatures.all,
        report: report([
          ('media', StartupStepOutcome.ok),
          ('recognition', StartupStepOutcome.ok),
        ]),
      );
      expect(rowText(tester), '녹음 켬 · 인식 켬 · 수식 엔진 켬');
      final scheme = Theme.of(tester.element(find.byKey(featureKey)))
          .colorScheme;
      expect(rowColor(tester), isNot(scheme.error));
    });

    testWidgets('off in the build (the module was not even made)', (
      tester,
    ) async {
      const build = AppFeatures(media: false, recognition: false);
      await pumpFeatures(
        tester,
        compileTime: build,
        started: build,
        report: report(const []),
      );
      expect(rowText(tester), '녹음 꺼짐(빌드) · 인식 꺼짐(빌드) · 수식 엔진 꺼짐(인식 꺼짐)');
      final scheme = Theme.of(tester.element(find.byKey(featureKey)))
          .colorScheme;
      expect(rowColor(tester), scheme.error);
    });

    testWidgets('off in the developer menu (skipped steps)', (tester) async {
      await pumpFeatures(
        tester,
        compileTime: const AppFeatures(mathEngine: false),
        started: const AppFeatures(recognition: false, mathEngine: false),
        report: report([
          ('media', StartupStepOutcome.ok),
          ('recognition', StartupStepOutcome.skipped),
        ]),
      );
      expect(rowText(tester), '녹음 켬 · 인식 꺼짐(개발자 메뉴) · 수식 엔진 꺼짐(빌드)');
      // The skipped step is in the startup row too.
      expect(find.textContaining('recognition 0ms (skipped)'), findsOneWidget);
    });

    testWidgets('failed start (media timed out, recognition failed)', (
      tester,
    ) async {
      await pumpFeatures(
        tester,
        compileTime: AppFeatures.all,
        started: AppFeatures.all,
        report: report([
          ('media', StartupStepOutcome.timedOut),
          ('recognition', StartupStepOutcome.failedNonCritical),
        ]),
      );
      expect(rowText(tester), '녹음 시작 실패 · 인식 시작 실패 · 수식 엔진 꺼짐(인식 꺼짐)');
    });

    testWidgets('진단 정보 복사 carries the same line and the skipped step', (
      tester,
    ) async {
      final copied = _mockClipboard(tester);
      await pumpFeatures(
        tester,
        compileTime: AppFeatures.all,
        started: const AppFeatures(media: false),
        report: report([
          ('media', StartupStepOutcome.skipped),
          ('recognition', StartupStepOutcome.ok),
        ]),
      );
      await tester.tap(find.byKey(const Key('about-copy-diagnostics')));
      await tester.pump();
      expect(copied, hasLength(1));
      expect(copied.single, contains('\n기능: 녹음 꺼짐(개발자 메뉴) · 인식 켬 · 수식 엔진 켬\n'));
      expect(copied.single, contains('media 0ms skipped'));
    });

    testWidgets('landscape: the row fits', (tester) async {
      await pumpFeatures(
        tester,
        compileTime: const AppFeatures(mathEngine: false),
        started: const AppFeatures(media: false, mathEngine: false),
        report: report([('media', StartupStepOutcome.skipped)]),
        logical: ipadLandscape,
      );
      expect(find.byKey(featureKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
