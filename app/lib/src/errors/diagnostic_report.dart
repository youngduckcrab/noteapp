/// The '진단 정보' text (docs/plans/01-infra.md 4.5.3, 6.7).
library;

import 'package:note_core/note_core.dart';

import '../bootstrap/startup_report.dart';
import '../features/app_features.dart';
import '../features/feature_status.dart';
import '../runtime/build_info.dart';
import '../runtime/runtime_info.dart';
import 'app_error_log.dart';

/// Plain-text report the user pastes into chat or a GitHub issue.
abstract final class DiagnosticReport {
  /// Longest report.
  static const int maxLength = 8000;

  /// Max 8000 chars. Sections: header, build, runtime, startup (every step
  /// with its outcome — a feature module switched off is 'skipped'), (2차
  /// 6.18) features ([appFeatureStatusLine] of [features]), storage
  /// (CORE StorageInfo — backend, durable, multi-tab, persistGranted, usage /
  /// quota, missing features), persistence (CORE PersistenceStatus — pending,
  /// last commit + latency, consecutive failures), last [maxErrors] errors
  /// (newest first) with [maxStackLines] lines each.
  static String format({
    required BuildInfo build,
    required RuntimeInfo runtime,
    StartupReport? startup,
    Map<AppFeature, AppFeatureState>? features,
    StorageInfo? storage,
    PersistenceStatus? persistence,
    required List<AppErrorRecord> errors,
    DateTime? now,
    int maxErrors = 5,
    int maxStackLines = 15,
  }) {
    final at = now ?? DateTime.now();
    DateTime zoned(DateTime t) => at.isUtc ? t.toUtc() : t.toLocal();
    final builtAt = build.builtAt == null ? '' : ', ${_iso(build.builtAt!)}';
    final standalone = runtime.isStandalone ? '예' : '아니요';
    final persistenceText = persistence == null
        ? _unknown
        : _persistence(persistence, at);
    final lines = <String>[
      '[$_title] ${_date(at)} ${_time(at)} (${_offset(at)})',
      '빌드: ${build.displayLabel} ${build.channel.name}$builtAt',
      runtime.isWeb
          ? '실행: 웹 · ${runtime.rendererLabel} · 홈 화면 앱: $standalone'
          : '실행: ${runtime.rendererLabel}',
      '브라우저: ${runtime.userAgent ?? _unknown}',
      '시작: ${startup == null ? _unknown : _startup(startup)}',
      '기능: ${features == null ? _unknown : appFeatureStatusLine(features)}',
      '저장소: ${storage == null ? _unknown : _storage(storage)}',
      '저장 상태: $persistenceText',
    ];

    final shown = errors.length <= maxErrors
        ? errors
        : errors.sublist(errors.length - maxErrors);
    if (errors.isEmpty) {
      lines.add('오류 없음');
    } else {
      lines.add('오류 ${errors.length}건 (최근 순, 최대 $maxErrors건)');
      for (var i = shown.length - 1; i >= 0; i--) {
        final record = shown[i];
        final number = errors.length - shown.length + i + 1;
        lines.add(
          '--- #$number ${_time(zoned(record.time))} ${record.source.name}'
          '${record.fatal ? ' (fatal)' : ''} ---',
        );
        lines.add(record.summary);
        if (record.details != null) lines.add(record.details!);
        final stack = record.stackTrace;
        if (stack != null) {
          final stackLines = stack.trimRight().split('\n');
          lines.addAll(stackLines.take(maxStackLines));
          if (stackLines.length > maxStackLines) {
            lines.add('… (${stackLines.length - maxStackLines}줄 생략)');
          }
        }
      }
    }
    final text = lines.join('\n');
    if (text.length <= maxLength) return text;
    const cut = '\n…(진단 정보가 길어 잘렸어요)';
    return '${text.substring(0, maxLength - cut.length)}$cut';
  }

  static const String _title = '필기노트 진단 정보';
  static const String _unknown = '알 수 없음';

  static String _startup(StartupReport report) {
    final steps = [
      for (final step in report.steps)
        '${step.id} ${_ms(step.elapsed)} ${step.outcome.name}',
    ];
    final page = report.sinceNavigationStart;
    return [
      if (page != null) '페이지 열기→준비 ${_ms(page)} / ',
      '부트스트랩 ${_ms(report.bootstrapElapsed)}',
      if (steps.isNotEmpty) ' (${steps.join(', ')})',
    ].join();
  }

  static String _storage(StorageInfo info) {
    final usage = info.usageBytes;
    final quota = info.quotaBytes;
    return [
      info.backend.name,
      if (!info.isDurable) '임시 저장(새로고침하면 사라짐)',
      switch (info.persistGranted) {
        true => '영구 보관 허용',
        false => '영구 보관 안 됨',
        null => '영구 보관 $_unknown',
      },
      info.isMultiTabSafe ? '다중 탭 안전' : '다중 탭 위험',
      usage == null && quota == null
          ? '사용량 $_unknown'
          : '${usage == null ? '?' : _bytes(usage)} / '
                '${quota == null ? '?' : _bytes(quota)}',
      info.missingBrowserFeatures.isEmpty
          ? '부족한 기능 없음'
          : '부족한 기능: ${info.missingBrowserFeatures.join(', ')}',
    ].join(' · ');
  }

  static String _persistence(PersistenceStatus status, DateTime at) {
    DateTime fromEpoch(int ms) =>
        DateTime.fromMillisecondsSinceEpoch(ms, isUtc: at.isUtc);
    final committed = status.lastCommittedAt;
    final latency = status.lastCommitLatency;
    final errorAt = status.lastErrorAt;
    final error = status.lastError;
    return [
      '대기 ${status.pendingOps}건${status.isWriting ? ' (저장 중)' : ''}',
      committed == null
          ? '마지막 저장 없음'
          : '마지막 저장 ${_time(fromEpoch(committed))}'
                '${latency == null ? '' : ' (${_ms(latency)})'}',
      '연속 실패 ${status.consecutiveFailures}',
      if (error != null) _lastError(error, errorAt, fromEpoch),
    ].join(' · ');
  }

  static String _lastError(
    Object error,
    int? errorAt,
    DateTime Function(int) fromEpoch,
  ) {
    final at = errorAt == null ? '' : ' ${_time(fromEpoch(errorAt))}';
    return '마지막 오류$at ${_shorten('$error', 200)}';
  }

  static String _shorten(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max - 1)}…';

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _date(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

  static String _time(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  static String _offset(DateTime t) {
    final minutes = t.timeZoneOffset.inMinutes;
    final sign = minutes < 0 ? '-' : '+';
    final abs = minutes.abs();
    return '$sign${_two(abs ~/ 60)}:${_two(abs % 60)}';
  }

  static String _iso(DateTime t) {
    final u = t.toUtc();
    return '${_date(u)}T${_time(u)}Z';
  }

  /// `1,234ms`.
  static String _ms(Duration d) => '${_grouped(d.inMilliseconds)}ms';

  static String _grouped(int value) {
    final digits = '${value.abs()}';
    final out = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// `12.3MB` (1024-based, one decimal from KB up).
  static String _bytes(int bytes) {
    const units = ['KB', 'MB', 'GB', 'TB'];
    if (bytes < 1024) return '${bytes}B';
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(1)}${units[unit]}';
  }
}
