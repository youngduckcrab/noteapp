/// The in-memory error log of the app shell (docs/plans/01-infra.md 4.5.3,
/// 6.7).
library;

import 'package:flutter/foundation.dart';

enum AppErrorSource { flutter, platform, provider, bootstrap, module, manual }

/// Longest [AppErrorRecord.summary].
const int _maxSummary = 300;

/// Longest [AppErrorRecord.stackTrace].
const int _maxStack = 4000;

String _truncate(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max - 1)}…';

@immutable
final class AppErrorRecord {
  const AppErrorRecord({
    required this.time,
    required this.source,
    required this.summary,
    this.details,
    this.stackTrace,
    this.fatal = false,
  });

  /// summary = details.exceptionAsString() truncated to 300 chars;
  /// details = details.context + library; stack truncated to 4000 chars.
  factory AppErrorRecord.fromFlutterErrorDetails(
    FlutterErrorDetails details, {
    DateTime? now,
  }) {
    final context = details.context?.toDescription().trim();
    final library = details.library;
    final parts = [
      if (context != null && context.isNotEmpty) context,
      if (library != null && library.isNotEmpty) '($library)',
    ];
    final stack = details.stack?.toString();
    return AppErrorRecord(
      time: now ?? DateTime.now(),
      source: AppErrorSource.flutter,
      summary: _truncate(details.exceptionAsString(), _maxSummary),
      details: parts.isEmpty ? null : parts.join(' '),
      stackTrace: stack == null || stack.isEmpty
          ? null
          : _truncate(stack, _maxStack),
    );
  }

  factory AppErrorRecord.fromError(
    Object error,
    StackTrace? stackTrace, {
    required AppErrorSource source,
    bool fatal = false,
    DateTime? now,
  }) {
    final stack = stackTrace?.toString();
    return AppErrorRecord(
      time: now ?? DateTime.now(),
      source: source,
      summary: _truncate('$error', _maxSummary),
      stackTrace: stack == null || stack.isEmpty
          ? null
          : _truncate(stack, _maxStack),
      fatal: fatal,
    );
  }

  final DateTime time;
  final AppErrorSource source;
  final String summary;
  final String? details;
  final String? stackTrace;
  final bool fatal;

  @override
  String toString() => 'AppErrorRecord(${source.name}: $summary)';
}

/// In-memory ring buffer. Oldest record is dropped when full.
///
/// Listeners are notified synchronously from [add], which can run inside a
/// frame (FlutterError.onError during build): a widget that rebuilds on
/// this log must schedule its setState after the frame.
final class AppErrorLog extends ChangeNotifier {
  AppErrorLog({this.capacity = 100}) : assert(capacity > 0);

  final int capacity;

  final List<AppErrorRecord> _records = [];
  int _total = 0;

  /// Oldest first, unmodifiable.
  List<AppErrorRecord> get records => List.unmodifiable(_records);

  /// Total records ever added, including dropped ones.
  int get totalCount => _total;

  void add(AppErrorRecord record) {
    _total++;
    _records.add(record);
    if (_records.length > capacity) {
      _records.removeRange(0, _records.length - capacity);
    }
    notifyListeners();
  }

  /// Removes the kept records; [totalCount] keeps counting.
  void clear() {
    if (_records.isEmpty) return;
    _records.clear();
    notifyListeners();
  }
}
