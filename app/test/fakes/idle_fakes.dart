// Fakes for idle-task tests (docs/plans/m5-7/01-infra.md 6.5, 6.7 '시험
// 이음새'): an AppIdleContext without widgets and a recording
// IndexerHandleReader — the indexers are `final class`, so tests count
// start / dispose through the module's injection argument, never through a
// provider override.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:noteapp/src/bootstrap/idle_tasks.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/idle_indexers.dart';
import 'package:noteapp/src/web/web_platform.dart';

import 'fake_web_platform.dart';

/// AppIdleContext over [container]; [dispose] runs the callbacks in reverse
/// order like the runner does.
final class FakeIdleContext implements AppIdleContext {
  FakeIdleContext({
    ProviderContainer? container,
    AppErrorLog? errorLog,
    WebPlatform? web,
  }) : container = container ?? ProviderContainer.test(),
       errorLog = errorLog ?? AppErrorLog(),
       web = web ?? FakeWebPlatform();

  final ProviderContainer container;
  @override
  final AppErrorLog errorLog;
  @override
  final WebPlatform web;
  final List<FutureOr<void> Function()> callbacks = [];
  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  @override
  void onDispose(FutureOr<void> Function() callback) {
    if (_disposed) {
      unawaited(Future<void>.sync(callback));
      return;
    }
    callbacks.add(callback);
  }

  Future<void> dispose() async {
    _disposed = true;
    while (callbacks.isNotEmpty) {
      await callbacks.removeLast()();
    }
  }
}

/// A recording IndexerHandleReader: [reader] hands out one handle whose
/// start / dispose calls are counted; [available] false → the reader
/// returns null (web, no recognizer).
final class RecordingIndexer {
  RecordingIndexer({this.available = true, this.startError});

  final bool available;
  final Object? startError;
  int reads = 0;
  int starts = 0;
  int disposes = 0;

  IndexerHandle? reader(AppIdleContext context) {
    reads++;
    if (!available) return null;
    return (
      start: () {
        starts++;
        if (startError case final error?) {
          Error.throwWithStackTrace(error, StackTrace.current);
        }
      },
      dispose: () async {
        disposes++;
      },
    );
  }
}
