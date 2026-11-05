// CoreModule (docs/plans/01-infra.md 4.5.9, 6.4, 9.1; contract 7.2.12 /
// 7.3.3 / 7.4.3): config with absolute URLs, publish + override, flush,
// close, persistence errors, reset, and the late store after a timeout
// (INFRA-2-9, fake_async).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_note_store_opener.dart';
import '../fakes/fake_web_platform.dart';

const _runtime = RuntimeInfo(
  isWeb: true,
  renderer: WebRenderer.canvasKit,
  isStandalone: false,
);

AppModuleContext _context({
  FakeWebPlatform? web,
  AppErrorLog? errorLog,
  OwnerId ownerId = kLocalOwnerId,
}) => AppModuleContext(
  buildInfo: BuildInfo.local,
  runtimeInfo: _runtime,
  web: web ?? FakeWebPlatform(),
  ownerId: ownerId,
  errorLog: errorLog ?? AppErrorLog(),
);

PersistenceStatus _status({
  Object? lastError,
  EpochMillis? lastErrorAt,
  int consecutiveFailures = 0,
  int pendingOps = 0,
}) => PersistenceStatus(
  pendingOps: pendingOps,
  isWriting: false,
  lastError: lastError,
  lastErrorAt: lastErrorAt,
  consecutiveFailures: consecutiveFailures,
);

/// Lets the status stream deliver (it sends asynchronously).
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('id, label, critical, 20 s timeout', () {
    final module = CoreModule();
    expect(CoreModule.moduleId, 'core');
    expect(module.id, 'core');
    expect(module.label, '노트 저장소 여는 중');
    expect(module.critical, isTrue);
    expect(module.startTimeout, const Duration(seconds: 20));
    expect(module.resetLocalData, isNotNull);
  });

  group('config', () {
    test('ownerId from the context; static files as ABSOLUTE URLs against '
        'document.baseURI (계약 7.2.12 · 7.4.3)', () async {
      final opener = fakeOpenNoteStore();
      final web = FakeWebPlatform(baseUri: Uri.parse('https://n.web.app/'));
      await CoreModule(open: opener.call)
          .start(_context(web: web, ownerId: 'owner-7'));

      final config = opener.lastConfig!;
      expect(opener.openCount, 1);
      expect(config.ownerId, 'owner-7');
      expect(config.web.sqlite3WasmPath, 'https://n.web.app/sqlite3.wasm');
      expect(config.web.driftWorkerPath, 'https://n.web.app/drift_worker.js');
      expect(Uri.parse(config.web.sqlite3WasmPath).isAbsolute, isTrue);
      expect(Uri.parse(config.web.driftWorkerPath).isAbsolute, isTrue);
      // Every other field keeps CORE's default.
      const defaults = NoteStoreConfig();
      expect(config.databaseName, defaults.databaseName);
      expect(config.web.blobDatabaseName, defaults.web.blobDatabaseName);
      expect(config.inMemory, isFalse);
      expect(config.nativeDatabasePath, isNull);
      expect(config.requestPersistentStorage, isTrue);
      expect(config.seedDefaultPenPresets, isTrue);
      expect(config.trashRetention, defaults.trashRetention);
      expect(config.clock, isNull);
      expect(config.idGenerator, isNull);
    });

    test('a deep page (/notes/x) still gets URLs at the base, also under '
        'a <base href> sub-path', () {
      // FakeWebPlatform resolves against document.baseURI, as the browser
      // does; the page location (/notes/x) plays no part.
      for (final (base, expected) in [
        ('https://n.web.app/', 'https://n.web.app/sqlite3.wasm'),
        (
          'https://p--b-1.web.app/app/',
          'https://p--b-1.web.app/app/sqlite3.wasm',
        ),
      ]) {
        final web = FakeWebPlatform(baseUri: Uri.parse(base));
        final config = defaultNoteStoreConfig(_context(web: web));
        expect(config.web.sqlite3WasmPath, expected);
        expect(config.web.sqlite3WasmPath, isNot(contains('/notes/')));
      }
    });

    test('a custom configFor is used', () async {
      final opener = fakeOpenNoteStore();
      const custom = NoteStoreConfig(inMemory: true);
      await CoreModule(
        open: opener.call,
        configFor: (_) => custom,
      ).start(_context());
      expect(opener.lastConfig, same(custom));
    });
  });

  group('lifetime', () {
    test('publishes the store; overrides() is noteStoreProvider only, with '
        'the same instance', () async {
      final store = CountingNoteStore();
      final context = _context();
      final module = CoreModule(open: fakeOpenNoteStore(store: store).call);
      await module.start(context);
      expect(context.require<NoteStore>(), same(store));

      final overrides = module.overrides();
      expect(overrides, hasLength(1));
      final container = ProviderContainer.test(overrides: overrides);
      expect(container.read(noteStoreProvider), same(store));
      await module.stop();
    });

    test('overrides() before a successful start throws', () {
      expect(() => CoreModule().overrides(), throwsStateError);
    });

    test('onAppHidden → flush; stop → status unsubscribed, then close '
        '(once)', () async {
      final store = CountingNoteStore();
      final module = CoreModule(open: fakeOpenNoteStore(store: store).call);
      await module.onAppHidden(); // not started: nothing
      expect(store.flushCount, 0);
      await module.start(_context());
      await _settle();
      expect(store.hasStatusListeners, isTrue);

      await module.onAppHidden();
      expect(store.flushCount, 1);

      await module.stop();
      expect(store.hasStatusListeners, isFalse);
      expect(store.closeCount, 1);
      await module.stop();
      await module.onAppHidden();
      expect(store.closeCount, 1);
      expect(store.flushCount, 1);
    });

    test('NoteStoreOpenException propagates unchanged; nothing published', () {
      const error = NoteStoreOpenException(
        NoteStoreOpenFailure.corrupted,
        'bad header',
      );
      final context = _context();
      final module = CoreModule(open: fakeOpenNoteStore(error: error).call);
      expect(module.start(context), throwsA(same(error)));
      expect(context.maybe<NoteStore>(), isNull);
    });
  });

  group('reset', () {
    test('canResetAfter (6.7): migrationFailed, corrupted, unknown only', () {
      final module = CoreModule();
      final expected = {
        NoteStoreOpenFailure.storageUnavailable: false,
        NoteStoreOpenFailure.migrationFailed: true,
        NoteStoreOpenFailure.corrupted: true,
        NoteStoreOpenFailure.newerSchema: false,
        NoteStoreOpenFailure.unknown: true,
      };
      expect(expected.keys, unorderedEquals(NoteStoreOpenFailure.values));
      for (final MapEntry(:key, :value) in expected.entries) {
        expect(
          module.canResetAfter(NoteStoreOpenException(key, 'x')),
          value,
          reason: key.name,
        );
      }
      expect(
        module.canResetAfter(TimeoutException('slow', Duration.zero)),
        isFalse,
      );
      expect(module.canResetAfter(StateError('other')), isFalse);
    });

    test(
      'resetLocalData erases the config of the last start attempt',
      () async {
        final eraser = RecordingLocalDataEraser();
        final opener = fakeOpenNoteStore(
          error: const NoteStoreOpenException(
            NoteStoreOpenFailure.migrationFailed,
            'v3 → v4',
          ),
        );
        final module = CoreModule(
          open: opener.call,
          deleteLocalData: eraser.call,
        );
        await expectLater(
          module.start(_context(ownerId: 'o-1')),
          throwsA(isA<NoteStoreOpenException>()),
        );
        await module.resetLocalData!();
        expect(eraser.calls, [same(opener.lastConfig)]);
        expect(eraser.calls.single.ownerId, 'o-1');
      },
    );

    test('resetLocalData passes the eraser failure on', () async {
      final eraser = RecordingLocalDataEraser(error: StateError('locked'));
      final module = CoreModule(
        open: fakeOpenNoteStore(
          error: const NoteStoreOpenException(
            NoteStoreOpenFailure.unknown,
            'x',
          ),
        ).call,
        deleteLocalData: eraser.call,
      );
      await expectLater(module.start(_context()), throwsA(anything));
      await expectLater(module.resetLocalData!(), throwsStateError);
    });

    test('resetLocalData before any start throws', () async {
      await expectLater(CoreModule().resetLocalData!(), throwsStateError);
    });
  });

  group('persistence errors → errorLog (source: module)', () {
    test('first event without an error → nothing; each new lastErrorAt → '
        'one record; the same error again → nothing', () async {
      final store = CountingNoteStore();
      final log = AppErrorLog();
      final module = CoreModule(open: fakeOpenNoteStore(store: store).call);
      await module.start(_context(errorLog: log));
      await _settle();
      expect(log.records, isEmpty);

      store.emitStatus(
        _status(
          lastError: const FormatException('disk full'),
          lastErrorAt: 1000,
          consecutiveFailures: 1,
        ),
      );
      await _settle();
      expect(log.records, hasLength(1));
      final record = log.records.single;
      expect(record.source, AppErrorSource.module);
      expect(record.summary, contains('disk full'));
      expect(record.summary, contains('consecutiveFailures: 1'));
      expect(record.time, DateTime.fromMillisecondsSinceEpoch(1000));

      // Same error, other fields changed (pending ops) → no new record.
      store.emitStatus(
        _status(
          lastError: const FormatException('disk full'),
          lastErrorAt: 1000,
          consecutiveFailures: 1,
          pendingOps: 4,
        ),
      );
      await _settle();
      expect(log.records, hasLength(1));

      // The retry fails again → new lastErrorAt → one more record.
      store.emitStatus(
        _status(
          lastError: const FormatException('disk full'),
          lastErrorAt: 1400,
          consecutiveFailures: 2,
        ),
      );
      await _settle();
      expect(log.records, hasLength(2));
      expect(log.records.last.summary, contains('consecutiveFailures: 2'));

      // A success clears the error → nothing.
      store.emitStatus(_status(consecutiveFailures: 0));
      await _settle();
      expect(log.records, hasLength(2));
      await module.stop();

      // After stop nothing is recorded any more.
      store.emitStatus(_status(lastError: 'late', lastErrorAt: 9000));
      await _settle();
      expect(log.records, hasLength(2));
    });

    test('an error already in the first event is logged once', () async {
      final store = CountingNoteStore()
        ..emitStatus(
          _status(
            lastError: StateError('quota'),
            lastErrorAt: 500,
            consecutiveFailures: 3,
          ),
        );
      final log = AppErrorLog();
      final module = CoreModule(open: fakeOpenNoteStore(store: store).call);
      await module.start(_context(errorLog: log));
      await _settle();
      expect(log.records, hasLength(1));
      expect(log.records.single.summary, contains('quota'));
      expect(log.records.single.summary, contains('consecutiveFailures: 3'));
      await module.stop();
    });
  });

  group('late store after the 20 s timeout (INFRA-2-9)', () {
    test('module alone: not published, closed once; stop() does not close '
        'again', () {
      fakeAsync((async) {
        final gate = Completer<NoteStore>();
        final store = CountingNoteStore();
        final context = _context();
        final module = CoreModule(open: fakeOpenNoteStore(gate: gate).call);
        var startDone = false;
        unawaited(module.start(context).then((_) => startDone = true));
        async.flushMicrotasks();

        var cleanupDone = false;
        unawaited(module.onStartAbandoned().then((_) => cleanupDone = true));
        async.flushMicrotasks();
        expect(cleanupDone, isFalse);

        gate.complete(store);
        async.flushMicrotasks();
        expect(startDone, isTrue);
        expect(cleanupDone, isTrue);
        expect(context.maybe<NoteStore>(), isNull);
        expect(store.hasStatusListeners, isFalse);
        expect(store.closeCount, 1);
        expect(module.overrides, throwsStateError);

        unawaited(module.stop());
        unawaited(module.onStartAbandoned());
        async.flushMicrotasks();
        expect(store.closeCount, 1);
      });
    });

    test('through AppBootstrapper: timedOut, then the late store is closed '
        'once; shutdown waits for it and does not close again', () {
      fakeAsync((async) {
        final gate = Completer<NoteStore>();
        final store = CountingNoteStore();
        final log = AppErrorLog();
        final web = FakeWebPlatform();
        final bootstrapper = AppBootstrapper(
          modules: [CoreModule(open: fakeOpenNoteStore(gate: gate).call)],
          buildInfo: BuildInfo.local,
          runtimeInfo: _runtime,
          web: web,
          errorLog: log,
          ownerId: kLocalOwnerId,
        );
        BootstrapResult? result;
        unawaited(bootstrapper.run().then((r) => result = r));
        async.elapse(const Duration(seconds: 19));
        expect(result, isNull);
        async.elapse(const Duration(seconds: 1));
        final failure = result! as BootstrapFailure;
        expect(failure.moduleId, 'core');
        expect(failure.error, isA<TimeoutException>());
        expect(
          failure.report.steps.single.outcome,
          StartupStepOutcome.timedOut,
        );
        expect(failure.resetLocalData, isNull);
        final recordsAfterTimeout = log.records.length;

        gate.complete(store);
        async.flushMicrotasks();
        expect(store.closeCount, 1);
        expect(store.flushCount, 0);

        var shutDown = false;
        unawaited(bootstrapper.shutdown().then((_) => shutDown = true));
        async.elapse(const Duration(seconds: 3));
        expect(shutDown, isTrue);
        expect(store.closeCount, 1);
        expect(log.records, hasLength(recordsAfterTimeout));
      });
    });

    test('shutdown before the late open waits up to 2 s for the close', () {
      fakeAsync((async) {
        final gate = Completer<NoteStore>();
        final store = CountingNoteStore();
        final bootstrapper = AppBootstrapper(
          modules: [CoreModule(open: fakeOpenNoteStore(gate: gate).call)],
          buildInfo: BuildInfo.local,
          runtimeInfo: _runtime,
          web: FakeWebPlatform(),
          errorLog: AppErrorLog(),
          ownerId: kLocalOwnerId,
        );
        unawaited(bootstrapper.run());
        async.elapse(const Duration(seconds: 20));
        var shutDown = false;
        unawaited(bootstrapper.shutdown().then((_) => shutDown = true));
        async.elapse(const Duration(milliseconds: 500));
        expect(shutDown, isFalse);
        gate.complete(store);
        async.flushMicrotasks();
        expect(store.closeCount, 1);
        expect(shutDown, isTrue);
      });
    });

    test('a failing late close is logged once (source: module)', () {
      fakeAsync((async) {
        final gate = Completer<NoteStore>();
        final store = CountingNoteStore(closeError: StateError('close boom'));
        final log = AppErrorLog();
        final module = CoreModule(open: fakeOpenNoteStore(gate: gate).call);
        unawaited(module.start(_context(errorLog: log)));
        unawaited(module.onStartAbandoned());
        gate.complete(store);
        async.flushMicrotasks();
        expect(store.closeCount, 1);
        expect(log.records, hasLength(1));
        expect(log.records.single.source, AppErrorSource.module);
        expect(log.records.single.summary, contains('close boom'));
      });
    });

    test('a failing late open: no close, nothing more logged', () {
      fakeAsync((async) {
        final gate = Completer<NoteStore>();
        final log = AppErrorLog();
        final module = CoreModule(open: fakeOpenNoteStore(gate: gate).call);
        Object? startError;
        unawaited(
          module.start(_context(errorLog: log)).catchError((Object e) {
            startError = e;
          }),
        );
        var cleanupDone = false;
        unawaited(module.onStartAbandoned().then((_) => cleanupDone = true));
        gate.completeError(
          const NoteStoreOpenException(NoteStoreOpenFailure.unknown, 'late'),
        );
        async.flushMicrotasks();
        expect(cleanupDone, isTrue);
        expect(startError, isA<NoteStoreOpenException>());
        expect(log.records, isEmpty);
      });
    });

    test('abandoned before open was called: nothing to clean up', () async {
      await CoreModule().onStartAbandoned();
    });
  });
}
