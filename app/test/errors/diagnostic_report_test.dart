// DiagnosticReport.format (docs/plans/01-infra.md 4.5.3, 6.7 and 9.1).

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/errors/diagnostic_report.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';

final _now = DateTime.utc(2026, 11, 4, 9, 20, 31);

final _build = BuildInfo(
  version: '0.1.0',
  buildNumber: 42,
  gitSha: 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
  gitRef: 'main',
  channel: BuildChannel.live,
  builtAt: DateTime.utc(2026, 11, 4, 9, 10),
);

const _web = RuntimeInfo(
  isWeb: true,
  renderer: WebRenderer.canvasKit,
  isStandalone: true,
  userAgent: 'Mozilla/5.0 (iPad)',
);

const _startup = StartupReport(
  steps: [
    StartupStep(
      id: 'core',
      elapsed: Duration(milliseconds: 380),
      outcome: StartupStepOutcome.ok,
    ),
    StartupStep(
      id: 'pdf',
      elapsed: Duration(milliseconds: 3),
      outcome: StartupStepOutcome.ok,
    ),
    StartupStep(
      id: 'featureWiring',
      elapsed: Duration(milliseconds: 1),
      outcome: StartupStepOutcome.ok,
    ),
  ],
  bootstrapElapsed: Duration(milliseconds: 412),
  sinceNavigationStart: Duration(milliseconds: 1234),
);

const _storage = StorageInfo(
  backend: StorageBackend.webSharedIndexedDb,
  persistGranted: true,
  usageBytes: 12897485, // 12.3 MiB
  quotaBytes: 1288490189, // 1.2 GiB
);

final _persistence = PersistenceStatus(
  pendingOps: 0,
  isWriting: false,
  lastCommittedAt: DateTime.utc(2026, 11, 4, 9, 19, 58).millisecondsSinceEpoch,
  lastCommitLatency: const Duration(milliseconds: 23),
);

AppErrorRecord _error(
  String summary,
  DateTime time, {
  AppErrorSource source = AppErrorSource.manual,
  String? details,
  String? stack,
  bool fatal = false,
}) => AppErrorRecord(
  time: time,
  source: source,
  summary: summary,
  details: details,
  stackTrace: stack,
  fatal: fatal,
);

void main() {
  test('text snapshot in the 6.7 format', () {
    final stack = [for (var i = 0; i < 20; i++) '#$i frame $i'].join('\n');
    final text = DiagnosticReport.format(
      build: _build,
      runtime: _web,
      startup: _startup,
      storage: _storage,
      persistence: _persistence,
      errors: [
        _error('first', DateTime.utc(2026, 11, 4, 9, 17), fatal: true),
        _error(
          'second',
          DateTime.utc(2026, 11, 4, 9, 18),
          source: AppErrorSource.module,
        ),
        _error(
          'Bad state: third',
          DateTime.utc(2026, 11, 4, 9, 19, 2),
          source: AppErrorSource.flutter,
          details: 'while building X (noteapp)',
          stack: stack,
        ),
      ],
      now: _now,
    );
    const startupLine =
        '시작: 페이지 열기→준비 1,234ms / 부트스트랩 412ms '
        '(core 380ms ok, pdf 3ms ok, featureWiring 1ms ok)';
    const storageLine =
        '저장소: webSharedIndexedDb · 영구 보관 허용 · 다중 탭 안전 · '
        '12.3MB / 1.2GB · 부족한 기능 없음';
    expect(
      text,
      [
        '[필기노트 진단 정보] 2026-11-04 09:20:31 (+00:00)',
        '빌드: 0.1.0 (#42 · a1b2c3d · main) live, 2026-11-04T09:10:00Z',
        '실행: 웹 · CanvasKit (dart2js) · 홈 화면 앱: 예',
        '브라우저: Mozilla/5.0 (iPad)',
        startupLine,
        storageLine,
        '저장 상태: 대기 0건 · 마지막 저장 09:19:58 (23ms) · 연속 실패 0',
        '오류 3건 (최근 순, 최대 5건)',
        '--- #3 09:19:02 flutter ---',
        'Bad state: third',
        'while building X (noteapp)',
        for (var i = 0; i < 15; i++) '#$i frame $i',
        '… (5줄 생략)',
        '--- #2 09:18:00 module ---',
        'second',
        '--- #1 09:17:00 manual (fatal) ---',
        'first',
      ].join('\n'),
    );
  });

  test('unknown values: startup, storage, persistence, user agent', () {
    final text = DiagnosticReport.format(
      build: BuildInfo.local,
      runtime: const RuntimeInfo(
        isWeb: false,
        renderer: WebRenderer.notWeb,
        isStandalone: false,
      ),
      errors: const [],
      now: _now,
    );
    final lines = text.split('\n');
    expect(lines[1], '빌드: 0.0.0 (#0 · local · local) local');
    expect(lines[2], '실행: 네이티브');
    expect(lines[3], '브라우저: 알 수 없음');
    expect(lines[4], '시작: 알 수 없음');
    expect(lines[5], '저장소: 알 수 없음');
    expect(lines[6], '저장 상태: 알 수 없음');
    expect(lines.last, '오류 없음');
  });

  test('CORE StorageInfo and PersistenceStatus variants', () {
    final text = DiagnosticReport.format(
      build: _build,
      runtime: _web,
      startup: const StartupReport(
        steps: [],
        bootstrapElapsed: Duration(milliseconds: 2500),
      ),
      storage: const StorageInfo(
        backend: StorageBackend.webInMemory,
        missingBrowserFeatures: ['opfs', 'sharedWorker'],
        persistGranted: false,
        usageBytes: 900,
      ),
      persistence: PersistenceStatus(
        pendingOps: 4,
        isWriting: true,
        lastError: StateError('disk full'),
        lastErrorAt: DateTime.utc(2026, 11, 4, 9, 19).millisecondsSinceEpoch,
        consecutiveFailures: 3,
      ),
      errors: const [],
      now: _now,
    );
    final lines = text.split('\n');
    expect(lines[4], '시작: 부트스트랩 2,500ms');
    expect(
      lines[5],
      '저장소: webInMemory · 임시 저장(새로고침하면 사라짐) · 영구 보관 안 됨 · '
      '다중 탭 안전 · 900B / ? · 부족한 기능: opfs, sharedWorker',
    );
    expect(
      lines[6],
      '저장 상태: 대기 4건 (저장 중) · 마지막 저장 없음 · 연속 실패 3 · '
      '마지막 오류 09:19:00 Bad state: disk full',
    );

    final unsafe = DiagnosticReport.format(
      build: _build,
      runtime: _web,
      storage: const StorageInfo(backend: StorageBackend.webUnsafeIndexedDb),
      errors: const [],
      now: _now,
    ).split('\n')[5];
    expect(
      unsafe,
      '저장소: webUnsafeIndexedDb · 영구 보관 알 수 없음 · 다중 탭 위험 · '
      '사용량 알 수 없음 · 부족한 기능 없음',
    );
  });

  test('local time zone offset in the header', () {
    final local = DateTime(2026, 11, 4, 18, 20, 31);
    final header = DiagnosticReport.format(
      build: _build,
      runtime: _web,
      errors: const [],
      now: local,
    ).split('\n').first;
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final h = offset.inHours.abs().toString().padLeft(2, '0');
    final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    expect(header, '[필기노트 진단 정보] 2026-11-04 18:20:31 ($sign$h:$m)');
  });

  test('at most 5 errors (newest first) and 8,000 characters', () {
    final longStack = [for (var i = 0; i < 30; i++) '#$i ${'x' * 200}']
        .join('\n');
    final errors = [
      for (var i = 1; i <= 7; i++)
        _error(
          'error $i ${'y' * 280}',
          DateTime.utc(2026, 11, 4, 9, i),
          stack: longStack,
        ),
    ];
    final text = DiagnosticReport.format(
      build: _build,
      runtime: _web,
      errors: errors,
      now: _now,
    );
    expect(text.length, DiagnosticReport.maxLength);
    expect(text, endsWith('…(진단 정보가 길어 잘렸어요)'));
    expect(text, contains('오류 7건 (최근 순, 최대 5건)'));
    expect(text, contains('--- #7 09:07:00 manual ---'));
    expect(text, isNot(contains('--- #2 ')));
    expect(text.indexOf('#7 09:07'), lessThan(text.indexOf('#6 09:06')));

    final short = DiagnosticReport.format(
      build: _build,
      runtime: _web,
      errors: errors,
      now: _now,
      maxErrors: 2,
      maxStackLines: 1,
    );
    expect(short.length, lessThan(DiagnosticReport.maxLength));
    expect('--- #'.allMatches(short).length, 2);
    expect(short, contains('… (29줄 생략)'));
  });
}
