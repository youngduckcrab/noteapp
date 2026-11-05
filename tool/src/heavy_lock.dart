/// The container-wide heavy test lock (docs/plans/m5-7/01-infra.md 6.13,
/// contract 00-overview 7.4.6 v2.1).
///
/// `media`- and `emulator`-tagged runs and full Chrome runs take one lock so
/// that only one of them runs at a time on the shared container, whichever
/// agent starts it.
///
/// - **Path**: fixed [defaultHeavyLockPath], or the value of
///   [heavyLockPathVariable]. Not `$TMPDIR` — it differs between agent
///   sessions, so it would not be container-wide.
/// - **Format** (one line, space separated):
///   `<pid> <start ISO-8601 UTC> <command — first 120 characters>`.
///   Taking the lock = creating the file
///   exclusively. A file whose pid is dead is stale and is reclaimed; a file
///   that cannot be read as that format (empty, no number) counts as stale
///   once it is older than [malformedLockAge] (a writer may be between
///   creating and writing it).
/// - **Nesting**: the holder passes `NOTEAPP_HEAVY_LOCK_HELD=1`
///   ([heavyLockHeldVariable]) to its children; a `ws test` / `ws
///   with-heavy-lock` started with it does not take the lock again (no
///   nested deadlock — SYNC review X-2).
/// - A one-line log of every take / release / time-out goes to
///   [heavyLockLogName] next to the lock file.
library;

import 'dart:io' as io;

import 'package:path/path.dart' as p;

/// The lock file used when [heavyLockPathVariable] is not set.
const String defaultHeavyLockPath = '/tmp/noteapp-heavy-tests.lock';

/// Environment variable that moves the lock file.
const String heavyLockPathVariable = 'NOTEAPP_HEAVY_LOCK';

/// Environment variable (`1`) the lock holder passes to its children.
const String heavyLockHeldVariable = 'NOTEAPP_HEAVY_LOCK_HELD';

/// Name of the log written next to the lock file.
const String heavyLockLogName = 'noteapp-heavy-tests.log';

/// Exit code of `ws test` / `ws with-heavy-lock` when the lock did not come
/// free in time.
const int heavyLockTimeoutExitCode = 4;

/// Default waiting time (`--heavy-lock-timeout` / `--timeout`).
const Duration defaultHeavyLockTimeout = Duration(minutes: 20);

/// A lock file that does not parse is stale once it is this old.
const Duration malformedLockAge = Duration(minutes: 1);

/// How much of the command the lock file keeps.
const int heavyLockCommandLength = 120;

/// The lock file path for [environment].
String heavyLockPath(Map<String, String> environment) {
  final custom = environment[heavyLockPathVariable];
  return custom == null || custom.isEmpty ? defaultHeavyLockPath : custom;
}

/// Whether [environment] says a parent process already holds the lock.
bool heavyLockHeldByParent(Map<String, String> environment) =>
    environment[heavyLockHeldVariable] == '1';

/// The content of a lock file.
final class HeavyLockRecord {
  HeavyLockRecord({
    required this.pid,
    required DateTime started,
    required String command,
  }) : started = started.toUtc(),
       command = _shorten(command);

  /// Parses one lock file text; `null` when it is not in the format.
  static HeavyLockRecord? parse(String text) {
    final line = text.split('\n').first.trimRight();
    final match = RegExp(r'^(\d+) (\S+)(?: (.*))?$').firstMatch(line);
    if (match == null) return null;
    final pid = int.tryParse(match.group(1)!);
    final started = DateTime.tryParse(match.group(2)!);
    if (pid == null || pid <= 0 || started == null) return null;
    return HeavyLockRecord(
      pid: pid,
      started: started,
      command: match.group(3) ?? '',
    );
  }

  final int pid;

  /// Start time in UTC.
  final DateTime started;

  /// The command, newlines folded, at most [heavyLockCommandLength]
  /// characters.
  final String command;

  /// The lock file line (without the trailing newline).
  String format() => '$pid ${started.toIso8601String()} $command'.trimRight();

  static String _shorten(String command) {
    final flat = command.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= heavyLockCommandLength
        ? flat
        : flat.substring(0, heavyLockCommandLength);
  }

  @override
  String toString() => format();
}

/// A held lock. [release] deletes the lock file (only while it is still
/// ours) and is idempotent.
final class HeavyLockLease {
  HeavyLockLease._(this._locker, this.path, this.record, this.waited);

  final HeavyLocker _locker;

  /// The lock file.
  final String path;

  /// What this lease wrote into it.
  final HeavyLockRecord record;

  /// How long [HeavyLocker.acquire] waited.
  final Duration waited;

  bool _released = false;

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _heldLeases.remove(this);
    final file = io.File(path);
    try {
      final current = HeavyLockRecord.parse(file.readAsStringSync());
      if (current != null && current.format() == record.format()) {
        file.deleteSync();
      }
    } on io.FileSystemException {
      // Already gone (reclaimed by someone who saw this process as dead).
    }
    _locker._appendLog(
      '${record.pid} released after '
      '${_locker._now().toUtc().difference(record.started).inSeconds}s',
      path,
    );
  }
}

final Set<HeavyLockLease> _heldLeases = {};

/// Releases every lease this process still holds — `ws` calls it before it
/// exits on SIGINT / SIGTERM ([TerminationGuard] in `tool/ws.dart`), where
/// the command's own `finally` does not run any more.
void releaseHeldHeavyLocks() {
  for (final lease in _heldLeases.toList()) {
    lease.release();
  }
}

/// Takes the lock file (see the library documentation).
final class HeavyLocker {
  HeavyLocker({
    bool Function(int pid)? isAlive,
    DateTime Function()? now,
    Future<void> Function(Duration duration)? sleep,
    int? ownPid,
    this.pollInterval = const Duration(seconds: 2),
    this.reportInterval = const Duration(minutes: 1),
  }) : _isAlive = isAlive ?? processIsAlive,
       _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed,
       ownPid = ownPid ?? io.pid;

  final bool Function(int pid) _isAlive;
  final DateTime Function() _now;
  final Future<void> Function(Duration duration) _sleep;

  /// The pid written into the lock file.
  final int ownPid;

  /// How often a held lock is looked at again.
  final Duration pollInterval;

  /// How often the waiting message is printed.
  final Duration reportInterval;

  /// Waits until the lock at [path] is free and takes it for [command].
  /// Prints the holder every [reportInterval] to [log]. Returns `null` when
  /// [timeout] passed first.
  Future<HeavyLockLease?> acquire({
    required String path,
    required String command,
    required Duration timeout,
    required StringSink log,
  }) async {
    final file = io.File(path);
    final start = _now();
    DateTime? lastReport;
    while (true) {
      final record = HeavyLockRecord(
        pid: ownPid,
        started: _now(),
        command: command,
      );
      if (_tryCreate(file, record)) {
        final waited = _now().difference(start);
        final lease = HeavyLockLease._(this, path, record, waited);
        _heldLeases.add(lease);
        _appendLog(
          '${record.pid} acquired after ${waited.inSeconds}s: '
          '${record.command}',
          path,
        );
        return lease;
      }
      final String text;
      try {
        text = file.readAsStringSync();
      } on io.FileSystemException {
        continue; // released between the create and the read: try again
      }
      final holder = HeavyLockRecord.parse(text);
      final stale = holder == null ? _isOld(file) : !_isAlive(holder.pid);
      if (stale && _reclaim(file, text)) {
        log.writeln(
          'ws: heavy test lock $path was stale '
          '(${holder == null ? 'unreadable' : 'pid ${holder.pid} is gone'}) '
          '— reclaimed',
        );
        _appendLog('$ownPid reclaimed stale lock: ${text.trim()}', path);
        continue;
      }
      final waited = _now().difference(start);
      if (waited >= timeout) {
        log.writeln(
          'ws: heavy test lock $path still held after '
          '${_duration(waited)} (${_describe(holder)}) — giving up',
        );
        _appendLog(
          '$ownPid gave up after ${waited.inSeconds}s: $command',
          path,
        );
        return null;
      }
      if (lastReport == null ||
          _now().difference(lastReport) >= reportInterval) {
        lastReport = _now();
        log.writeln(
          'ws: waiting for the heavy test lock (잠금 대기) $path: '
          '${_describe(holder)}',
        );
      }
      final remaining = timeout - waited;
      await _sleep(remaining < pollInterval ? remaining : pollInterval);
    }
  }

  bool _tryCreate(io.File file, HeavyLockRecord record) {
    try {
      file.parent.createSync(recursive: true);
      file.createSync(exclusive: true);
    } on io.FileSystemException {
      return false;
    }
    file.writeAsStringSync('${record.format()}\n', flush: true);
    return true;
  }

  bool _isOld(io.File file) {
    try {
      return _now().difference(file.lastModifiedSync()) >= malformedLockAge;
    } on io.FileSystemException {
      return false;
    }
  }

  /// Deletes the stale lock [file] if it still holds [seen]. A short
  /// exclusive file lock on `<path>.guard` makes the look-and-delete one
  /// step between `ws` processes, so two of them never both delete (the
  /// second would delete the first one's fresh lock).
  bool _reclaim(io.File file, String seen) {
    final guard = io.File('${file.path}.guard');
    io.RandomAccessFile? handle;
    try {
      handle = guard.openSync(mode: io.FileMode.append)
        ..lockSync(io.FileLock.blockingExclusive);
      if (file.readAsStringSync() != seen) return false;
      file.deleteSync();
      return true;
    } on io.FileSystemException {
      return false;
    } finally {
      try {
        handle?.unlockSync();
        handle?.closeSync();
      } on io.FileSystemException {
        // The guard is advisory; closing releases it anyway.
      }
    }
  }

  void _appendLog(String line, String lockPath) {
    try {
      io.File(p.join(p.dirname(lockPath), heavyLockLogName)).writeAsStringSync(
        '${_now().toUtc().toIso8601String()} $line\n',
        mode: io.FileMode.append,
        flush: true,
      );
    } on io.FileSystemException {
      // The log is informational only.
    }
  }

  String _describe(HeavyLockRecord? holder) => holder == null
      ? 'lock file being written or unreadable'
      : 'pid ${holder.pid}, started ${holder.started.toIso8601String()}, '
            'command ${holder.command}';
}

/// Whether a process with [pid] exists (`/proc/<pid>` on Linux, `kill -0`
/// elsewhere).
bool processIsAlive(int pid) {
  if (io.Platform.isWindows) {
    final result = io.Process.runSync('tasklist', ['/FI', 'PID eq $pid']);
    return '${result.stdout}'.contains(' $pid ');
  }
  if (io.Directory('/proc/self').existsSync()) {
    return io.Directory('/proc/$pid').existsSync();
  }
  return io.Process.runSync('kill', ['-0', '$pid']).exitCode == 0;
}

String _duration(Duration d) => d.inSeconds < 120
    ? '${d.inSeconds}s'
    : '${(d.inSeconds / 60).toStringAsFixed(1)} min';
