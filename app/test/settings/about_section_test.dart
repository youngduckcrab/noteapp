// AboutSection (docs/plans/01-infra.md 4.5.8, 9.1): shown values, diagnostics
// copy, license page, update check, and the backup flow — prepareBackup with
// a progress row → BackupReadySheet → deliverBackup → a snackbar per outcome;
// cancelling the wait (INFRA-3-3, 계약 7.2.9 v1.2) leaves no trace.
//
// The B2 fake store's exportBackupJson is UnimplementedError (계약 7.6):
// CountingNoteStore.exportBackupResult injects the bytes.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/settings/about_section.dart';
import 'package:noteapp/src/settings/backup_sheet.dart';
import 'package:noteapp/src/web/web_platform.dart';

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
}
