// test/helpers/recording_note_session.dart — 04-editor 9.1 (E-01).
import 'dart:async';

import 'package:note_core/note_core.dart' as core;

/// Delegating core.NoteSession that records openPage / closePage / execute /
/// executeAsync / undo / redo / flush calls (in order) and flags any execute made
/// while one of its streams is delivering (N-2 v1.1 re-entrancy rule). Installed with
/// core.noteSessionProvider.overrideWith(...) — test only.
class RecordingNoteSession implements core.NoteSession {
  RecordingNoteSession(this.inner);

  /// The real (fake-store) session every call is delegated to.
  final core.NoteSession inner;

  final List<String> _calls = [];
  int _delivering = 0;
  bool _executeDuringDelivery = false;
  Object? _rejectNext;

  /// e.g. ['openPage:p1', 'execute:add-strokes']. A call refused by
  /// [rejectNext] is recorded with a ':rejected' suffix.
  List<String> get calls => List.unmodifiable(_calls);

  final List<core.EditCommand> _commands = [];

  /// (v2) The commands handed to execute / executeAsync that reached the
  /// inner session, in order (cleared by [clearCalls]).
  List<core.EditCommand> get commands => List.unmodifiable(_commands);

  /// True once `execute` was called from inside a listener of one of this
  /// session's streams (noteStream, pagesStream, pageChanges, historyStream).
  bool get executeDuringDelivery => _executeDuringDelivery;

  /// True while a listener of one of this session's streams is running.
  bool get isDelivering => _delivering > 0;

  /// The next execute / executeAsync / undo / redo throws [error] without reaching the
  /// inner session (commit-failure injection, e.g. const core.ReadOnlyNoteException('race')).
  void rejectNext(Object error) => _rejectNext = error;

  /// Forgets the recorded calls and commands (the delivery flag stays).
  void clearCalls() {
    _calls.clear();
    _commands.clear();
  }

  int _activeSubscriptions = 0;

  /// Subscriptions to this session's streams that were not cancelled yet
  /// (a stream that ends by itself still counts).
  int get activeSubscriptions => _activeSubscriptions;

  /// Number of recorded calls equal to [call] (e.g. 'closePage:p1').
  int countOf(String call) => _calls.where((c) => c == call).length;

  Completer<void>? _pageLoadGate;

  /// From now on openPage waits for [releasePageLoads] before it reaches the
  /// inner session, so the page stays unloaded (loading cover) meanwhile.
  void holdPageLoads() => _pageLoadGate ??= Completer<void>();

  /// Lets the openPage calls held by [holdPageLoads] through.
  void releasePageLoads() {
    final gate = _pageLoadGate;
    _pageLoadGate = null;
    gate?.complete();
  }

  Object? _takeRejection() {
    final error = _rejectNext;
    _rejectNext = null;
    return error;
  }

  void _deliver(void Function() handler) {
    _delivering++;
    try {
      handler();
    } finally {
      _delivering--;
    }
  }

  Stream<T> _tracked<T>(Stream<T> stream) => _TrackedStream<T>(stream, this);

  // --- recorded members ------------------------------------------------------

  @override
  Future<core.PageContent> openPage(core.PageId pageId) {
    _calls.add('openPage:$pageId');
    final gate = _pageLoadGate;
    if (gate != null) return gate.future.then((_) => inner.openPage(pageId));
    return inner.openPage(pageId);
  }

  @override
  void closePage(core.PageId pageId) {
    _calls.add('closePage:$pageId');
    inner.closePage(pageId);
  }

  @override
  core.CommandReceipt execute(core.EditCommand command) {
    if (_delivering > 0) _executeDuringDelivery = true;
    final rejection = _takeRejection();
    if (rejection != null) {
      _calls.add('execute:${command.label}:rejected');
      Error.throwWithStackTrace(rejection, StackTrace.current);
    }
    _calls.add('execute:${command.label}');
    _commands.add(command);
    return inner.execute(command);
  }

  @override
  Future<core.CommandReceipt> executeAsync(core.EditCommand command) async {
    final rejection = _takeRejection();
    if (rejection != null) {
      _calls.add('executeAsync:${command.label}:rejected');
      Error.throwWithStackTrace(rejection, StackTrace.current);
    }
    _calls.add('executeAsync:${command.label}');
    _commands.add(command);
    return inner.executeAsync(command);
  }

  @override
  Future<core.UndoRedoResult> undo() async {
    final rejection = _takeRejection();
    if (rejection != null) {
      _calls.add('undo:rejected');
      Error.throwWithStackTrace(rejection, StackTrace.current);
    }
    _calls.add('undo');
    return inner.undo();
  }

  @override
  Future<core.UndoRedoResult> redo() async {
    final rejection = _takeRejection();
    if (rejection != null) {
      _calls.add('redo:rejected');
      Error.throwWithStackTrace(rejection, StackTrace.current);
    }
    _calls.add('redo');
    return inner.redo();
  }

  @override
  Future<void> flush() {
    _calls.add('flush');
    return inner.flush();
  }

  @override
  Future<void> close() {
    _calls.add('close');
    return inner.close();
  }

  @override
  void clearHistory() {
    _calls.add('clearHistory');
    inner.clearHistory();
  }

  // --- streams (delivery tracked) ---------------------------------------------

  @override
  Stream<core.Note> get noteStream => _tracked(inner.noteStream);

  @override
  Stream<List<core.Page>> get pagesStream => _tracked(inner.pagesStream);

  @override
  Stream<core.PageContentChange> pageChanges(core.PageId pageId) =>
      _tracked(inner.pageChanges(pageId));

  @override
  Stream<core.HistoryState> get historyStream => _tracked(inner.historyStream);

  // --- plain delegation ---------------------------------------------------------

  @override
  core.NoteId get noteId => inner.noteId;

  @override
  core.Note get note => inner.note;

  @override
  bool get isReadOnly => inner.isReadOnly;

  @override
  List<core.Page> get pages => inner.pages;

  @override
  core.PageContent? pageIfLoaded(core.PageId pageId) =>
      inner.pageIfLoaded(pageId);

  @override
  core.HistoryState get history => inner.history;

  @override
  bool get isClosed => inner.isClosed;
}

/// Wraps every data handler of [_inner] so the owner knows a listener runs.
final class _TrackedStream<T> extends Stream<T> {
  _TrackedStream(this._inner, this._owner);

  final Stream<T> _inner;
  final RecordingNoteSession _owner;

  @override
  bool get isBroadcast => _inner.isBroadcast;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = _TrackedSubscription<T>(
      _inner.listen(
        null,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
      _owner,
    );
    subscription.onData(onData);
    _owner._activeSubscriptions++;
    return subscription;
  }
}

final class _TrackedSubscription<T> implements StreamSubscription<T> {
  _TrackedSubscription(this._inner, this._owner);

  final StreamSubscription<T> _inner;
  final RecordingNoteSession _owner;

  @override
  void onData(void Function(T data)? handleData) {
    _inner.onData(
      handleData == null
          ? null
          : (T data) => _owner._deliver(() => handleData(data)),
    );
  }

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  bool get isPaused => _inner.isPaused;

  bool _cancelled = false;

  @override
  Future<void> cancel() {
    if (!_cancelled) {
      _cancelled = true;
      _owner._activeSubscriptions--;
    }
    return _inner.cancel();
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture<E>(futureValue);
}
