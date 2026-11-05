// lib/src/storage/watch_hub.dart (internal) — re-queried watch streams of the SQLite
// store (C-1: current value on listen, again after every commit that changes it).
//
// No timers: a watch re-runs its query when a committed transaction touched one of
// its kinds (or kv keys). The write queue awaits [WatchHub.committed] before it
// completes the jobs of that commit, so a repository Future completes after the
// watch streams have re-emitted, as in the fake store (4.5 head).
import 'dart:async';

import '../model/sync_entity.dart';

/// What one committed transaction wrote.
final class CommitTouch {
  const CommitTouch(this.kinds, this.kvKeys);
  final Set<EntityKind> kinds;
  final Set<String> kvKeys;
  bool get isEmpty => kinds.isEmpty && kvKeys.isEmpty;
}

final class WatchHub {
  final Set<_Watch<Object?>> _watches = {};
  bool _closed = false;

  /// A stream that runs [query] on listen and again after every commit for which
  /// [affects] is true; a value equal to the last one ([equals], default `==`) is
  /// not emitted again.
  Stream<T> watch<T>({
    required bool Function(CommitTouch touch) affects,
    required Future<T> Function() query,
    bool Function(T a, T b)? equals,
  }) => Stream<T>.multi((c) {
    if (_closed) {
      c.closeSync();
      return;
    }
    final w = _Watch<T>(affects, query, equals ?? (T a, T b) => a == b, c);
    _watches.add(w);
    c.onCancel = () {
      w.cancelled = true;
      _watches.remove(w);
    };
    w.refresh();
  });

  /// Re-runs the watches affected by [touch]; completes when they have emitted.
  Future<void> committed(CommitTouch touch) {
    if (touch.isEmpty || _watches.isEmpty) return Future<void>.value();
    final runs = [
      for (final w in _watches.toList())
        if (w.affects(touch)) w.refresh(),
    ];
    if (runs.isEmpty) return Future<void>.value();
    return Future.wait(runs);
  }

  /// Stops every watch (no further events) and closes its stream.
  void close() {
    if (_closed) return;
    _closed = true;
    for (final w in _watches.toList()) {
      w.cancelled = true;
      w.controller.closeSync();
    }
    _watches.clear();
  }
}

final class _Watch<T> {
  _Watch(this.affects, this.query, this.equals, this.controller);

  final bool Function(CommitTouch) affects;
  final Future<T> Function() query;
  final bool Function(T, T) equals;
  final MultiStreamController<T> controller;

  bool cancelled = false;
  bool _running = false;
  bool _dirty = false;
  bool _hasValue = false;
  T? _last;
  Completer<void>? _done;

  /// Runs the query (again, if one is running); completes after the run that
  /// started after this call has emitted.
  Future<void> refresh() {
    if (cancelled) return Future<void>.value();
    final done = _done ??= Completer<void>();
    if (_running) {
      _dirty = true;
    } else {
      _running = true;
      unawaited(_loop());
    }
    return done.future;
  }

  Future<void> _loop() async {
    do {
      _dirty = false;
      try {
        final v = await query();
        if (cancelled) break;
        if (!_hasValue || !equals(v, _last as T)) {
          _hasValue = true;
          _last = v;
          controller.add(v);
        }
      } on Object catch (e, s) {
        if (!cancelled) controller.addError(e, s);
      }
    } while (_dirty && !cancelled);
    _running = false;
    final d = _done;
    _done = null;
    d?.complete();
  }
}
