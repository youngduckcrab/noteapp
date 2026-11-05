// fakeOpenNoteStore and RecordingLocalDataEraser (docs/plans/01-infra.md
// 5.7): stand-ins for CORE's openNoteStore / deleteLocalNoteData.
import 'dart:async';

import 'package:note_core/note_core.dart';

import 'counting_note_store.dart';

/// An `openNoteStore` replacement that records its calls. Pass `.call` as
/// `CoreModule(open: …)`.
final class FakeNoteStoreOpener {
  FakeNoteStoreOpener({
    this.delay = Duration.zero,
    this.error,
    NoteStore? store,
    this.gate,
  }) : store = store ?? CountingNoteStore();

  /// How long open takes (fake time).
  final Duration delay;

  /// Thrown instead of returning a store.
  final Object? error;

  /// Returned when [gate] is null.
  final NoteStore store;

  /// When set, open completes with this completer's result (a late open
  /// after the start timeout, INFRA-2-9).
  final Completer<NoteStore>? gate;

  int openCount = 0;
  NoteStoreConfig? lastConfig;
  final List<NoteStoreConfig> configs = [];

  Future<NoteStore> call(NoteStoreConfig config) async {
    openCount++;
    lastConfig = config;
    configs.add(config);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (gate case final gate?) return gate.future;
    if (error case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return store;
  }
}

/// `fakeOpenNoteStore({delay, error, store, gate})` (5.7).
FakeNoteStoreOpener fakeOpenNoteStore({
  Duration delay = Duration.zero,
  Object? error,
  NoteStore? store,
  Completer<NoteStore>? gate,
}) => FakeNoteStoreOpener(delay: delay, error: error, store: store, gate: gate);

/// A `deleteLocalNoteData` replacement: records the configs it was called
/// with and throws [error] when set.
final class RecordingLocalDataEraser {
  RecordingLocalDataEraser({this.error, this.delay = Duration.zero});

  Object? error;
  Duration delay;
  final List<NoteStoreConfig> calls = [];

  Future<void> call(NoteStoreConfig config) async {
    calls.add(config);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }
}
