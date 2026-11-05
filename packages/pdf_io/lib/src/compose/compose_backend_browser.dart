// lib/src/compose/compose_backend_browser.dart — web compose backend (dedicated Worker,
// 06-pdf 6.11.6). Only *_browser.dart files may import dart:js_interop / package:web
// (contract 7.4.3); loaded only through compose_backend_factory.dart.
//
// The Worker runs pdfrx's pdfium_worker.js (its own pdfium.wasm instance, separate from the
// render worker) plus web/pdf_io_compose_ext.js, which adds the pdfioCompose* commands to
// the worker's `functions` table. Requests use the pdfrx worker protocol: {id, command,
// parameters} → {id, status: 'success' | 'error', result | error}. The worker is created on
// the first begin and terminated after PdfTuning.composeWorkerIdleTimeout without jobs, when
// an abort does not answer within 5 s, on a worker error, and on dispose.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../config.dart';
import '../errors.dart';
import '../export/compose_plan.dart';
import '../tuning.dart';
import 'compose_backend.dart';
import 'compose_layout.dart';

/// Web: dedicated Worker (pdfrx pdfium_worker.js + pdf_io_compose_ext.js), chunk 16 pages.
/// VM/native: FFI interpreter on the pdfrx background isolate, chunk 8 pages. Other: unsupported.
PdfComposeBackend createPlatformComposeBackend(PdfIoConfig config) =>
    BrowserPdfComposeBackend(config);

/// pdfrx's default module folder (PdfrxEntryFunctionsWasmImpl.defaultWasmModulePath).
const String _defaultModules = 'assets/packages/pdfrx/assets/';

/// The extension marks an unexpected pdfrx worker with this error (6.11.6).
const String _incompatible = 'pdfio-incompatible-pdfrx';

/// Internal (not exported): the Worker backend. [idleTimeout] and [abortTimeout] are
/// shortened by the browser tests only.
final class BrowserPdfComposeBackend implements PdfComposeBackend {
  BrowserPdfComposeBackend(
    this._config, {
    this.idleTimeout = PdfTuning.composeWorkerIdleTimeout,
    this.abortTimeout = const Duration(seconds: 5),
  });

  final PdfIoConfig _config;
  final Duration idleTimeout;
  final Duration abortTimeout;
  final Set<_BrowserComposeJob> _jobs = {};
  _ComposeWorker? _worker;
  Future<_ComposeWorker>? _starting;
  Timer? _idleTimer;
  int _nextJobId = 1;
  bool _disposed = false;

  /// Jobs begun here and not yet finished or aborted.
  int get openJobCount => _jobs.length;

  /// Whether a compose Worker is running (test hook for the idle shutdown).
  bool get hasWorker => _worker != null;

  /// Open jobs inside the running Worker (0 without one) — test hook for 'abort frees
  /// the job'.
  Future<int> debugWorkerJobCount() async {
    final worker = _worker;
    if (worker == null) return 0;
    final result = await worker.request('pdfioComposeJobCount', JSObject());
    return result!.getProperty<JSNumber>('count'.toJS).toDartInt;
  }

  @override
  bool get isSupported => true;

  @override
  Future<PdfComposeJob> begin(PdfComposePlan plan) async {
    if (_disposed) throw StateError('BrowserPdfComposeBackend is disposed');
    if (plan.pages.isEmpty) {
      throw ArgumentError.value(plan, 'plan', 'no output pages');
    }
    final pages = plan.encodePages();
    // Programming errors fail here, not in the worker.
    decodeComposePlan(pages, plan.sources.length);
    _idleTimer?.cancel();
    _idleTimer = null;
    final worker = await _ensureWorker();
    final jobId = _nextJobId++;
    final pagesBuffer = pages.buffer.toJS; // made here: transferred
    final transfer = <JSObject>[pagesBuffer];
    final sources = [
      for (final source in plan.sources) _buffer(source.bytes, transfer),
    ];
    final parameters = JSObject()
      ..setProperty('jobId'.toJS, jobId.toJS)
      ..setProperty('sources'.toJS, sources.toJS)
      ..setProperty('pages'.toJS, pagesBuffer);
    final job = _BrowserComposeJob(this, worker, jobId, plan.pages.length);
    _jobs.add(job); // counts as busy while the worker loads (no idle shutdown)
    try {
      final result = await worker.request(
        'pdfioComposeBegin',
        parameters,
        transfer: transfer,
      );
      final pageCount = result!.getProperty<JSNumber>('pageCount'.toJS);
      if (pageCount.toDartInt != plan.pages.length) {
        throw PdfIoException(
          PdfErrorCode.exportFailed,
          detail: '${pageCount.toDartInt} pages, plan has ${plan.pages.length}',
        );
      }
    } on Object {
      _jobClosed(job);
      rethrow;
    }
    if (_disposed) {
      await job.abort();
      throw StateError('BrowserPdfComposeBackend is disposed');
    }
    return job;
  }

  /// Aborts the open jobs and stops the worker; later [begin] calls throw StateError.
  @override
  Future<void> dispose() async {
    _disposed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    for (final job in _jobs.toList()) {
      await job.abort();
    }
    _stopWorker('compose backend disposed');
    try {
      await _starting;
    } on Object {
      // already reported to the begin that started it
    }
    _stopWorker('compose backend disposed');
  }

  Future<_ComposeWorker> _ensureWorker() {
    final running = _worker;
    if (running != null && !running.isDead) return Future.value(running);
    return _starting ??= _startWorker().whenComplete(() => _starting = null);
  }

  Future<_ComposeWorker> _startWorker() async {
    final base = Uri.parse(web.document.baseURI);
    final modules = base.resolve(
      _config.pdfiumWasmModulesUrl ?? _defaultModules,
    );
    final wasm = modules.resolve('pdfium.wasm').toString();
    final script = modules.resolve('pdfium_worker.js').toString();
    final extension = base.resolve(_config.composeExtensionUrl).toString();
    final source =
        'const pdfiumWasmUrl=${jsonEncode(wasm)};'
        'importScripts(${jsonEncode(script)});'
        'importScripts(${jsonEncode(extension)});';
    final blob = web.Blob(
      <JSAny>[source.toJS].toJS,
      web.BlobPropertyBag(type: 'application/javascript'),
    );
    final url = web.URL.createObjectURL(blob);
    final _ComposeWorker worker;
    try {
      worker = _ComposeWorker(web.Worker(url.toJS), _workerDied);
    } on Object catch (e) {
      web.URL.revokeObjectURL(url);
      throw PdfIoException(
        PdfErrorCode.engineUnavailable,
        detail: 'compose worker could not start',
        cause: e,
      );
    }
    try {
      await worker.request('init', JSObject());
    } on Object catch (e) {
      worker.terminate(e);
      throw PdfIoException(
        PdfErrorCode.engineUnavailable,
        detail: 'compose worker init failed: ${_detailOf(e)}',
        cause: e,
      );
    } finally {
      web.URL.revokeObjectURL(url);
    }
    if (_disposed) {
      worker.terminate(StateError('disposed'));
      throw StateError('BrowserPdfComposeBackend is disposed');
    }
    _worker = worker;
    return worker;
  }

  void _workerDied(_ComposeWorker worker) {
    if (identical(_worker, worker)) _worker = null;
  }

  void _stopWorker(String reason) {
    final worker = _worker;
    _worker = null;
    worker?.terminate(StateError(reason));
  }

  void _jobClosed(_BrowserComposeJob job) {
    _jobs.remove(job);
    if (_jobs.isNotEmpty || _worker == null || _disposed) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      _idleTimer = null;
      if (_jobs.isEmpty) _stopWorker('compose worker idle');
    });
  }
}

enum _JobPhase { open, finishing, closed }

final class _BrowserComposeJob implements PdfComposeJob {
  _BrowserComposeJob(this._backend, this._worker, this._jobId, this._pageCount);

  final BrowserPdfComposeBackend _backend;
  final _ComposeWorker _worker;
  final int _jobId;
  final int _pageCount;
  _JobPhase _phase = _JobPhase.open;
  Future<void>? _pending; // last addPages in flight
  Future<Uint8List>? _finishing;

  void _checkOpen(String member) {
    if (_phase != _JobPhase.open) {
      throw StateError('PdfComposeJob.$member after finish/abort');
    }
  }

  @override
  Future<void> addPages(List<PdfComposePageOps> pages) async {
    _checkOpen('addPages');
    final work = [
      for (final page in pages)
        if (!page.isEmpty) page,
    ];
    for (final page in work) {
      if (page.outputIndex < 0 || page.outputIndex >= _pageCount) {
        throw ArgumentError.value(
          page.outputIndex,
          'outputIndex',
          'not in 0..${_pageCount - 1}',
        );
      }
    }
    if (work.isEmpty) return;
    final transfer = <JSObject>[];
    final list = <JSAny?>[];
    for (final page in work) {
      list.add(
        JSObject()
          ..setProperty('outputIndex'.toJS, page.outputIndex.toJS)
          ..setProperty('verbs'.toJS, _buffer(page.verbs, transfer))
          ..setProperty('coords'.toJS, _buffer(page.coords, transfer))
          ..setProperty('paints'.toJS, _buffer(page.paints, transfer)),
      );
    }
    final parameters = JSObject()
      ..setProperty('jobId'.toJS, _jobId.toJS)
      ..setProperty('pages'.toJS, list.toJS);
    final call = _worker.request(
      'pdfioComposeAddPages',
      parameters,
      transfer: transfer,
    );
    _pending = call.then((_) {}, onError: (Object _) {});
    await call;
  }

  @override
  Future<Uint8List> finish() {
    _checkOpen('finish');
    _phase = _JobPhase.finishing;
    return _finishing = () async {
      try {
        final result = await _worker.request(
          'pdfioComposeFinish',
          JSObject()..setProperty('jobId'.toJS, _jobId.toJS),
        );
        final data = result!.getProperty<JSArrayBuffer>('data'.toJS);
        return data.toDart.asUint8List();
      } finally {
        _phase = _JobPhase.closed;
        _backend._jobClosed(this);
      }
    }();
  }

  @override
  Future<void> abort() async {
    switch (_phase) {
      case _JobPhase.closed:
        return;
      case _JobPhase.finishing:
        // finish() releases everything itself, also when it fails.
        await _finishing?.then((_) {}, onError: (Object _) {});
        return;
      case _JobPhase.open:
        _phase = _JobPhase.closed;
        try {
          if (_worker.isDead) return;
          await _pending;
          await _worker
              .request(
                'pdfioComposeAbort',
                JSObject()..setProperty('jobId'.toJS, _jobId.toJS),
              )
              .timeout(_backend.abortTimeout);
        } on Object {
          // No answer (or a dead worker): stop it; the next begin starts a new one.
          _worker.terminate(StateError('compose abort did not answer'));
        } finally {
          _backend._jobClosed(this);
        }
    }
  }
}

/// The ArrayBuffer to send for [data]: its own buffer when [data] covers all of it
/// (structured clone — the caller's list stays usable), else a copy that is transferred.
JSArrayBuffer _buffer(TypedData data, List<JSObject> transfer) {
  final whole =
      data.offsetInBytes == 0 &&
      data.lengthInBytes == data.buffer.lengthInBytes;
  if (whole) return data.buffer.toJS;
  final copy = Uint8List.fromList(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  final buffer = copy.buffer.toJS;
  transfer.add(buffer);
  return buffer;
}

String _detailOf(Object error) => switch (error) {
  PdfIoException(:final detail) => detail ?? '$error',
  _WorkerError(:final message) => message,
  _ => '$error',
};

/// An error answer of the worker ({status: 'error', error: e.stack}).
final class _WorkerError implements Exception {
  _WorkerError(String stack) : message = stack.split('\n').first.trim();
  final String message;

  @override
  String toString() => 'compose worker: $message';
}

/// One Worker and its open requests.
final class _ComposeWorker {
  _ComposeWorker(this._worker, this._onDied) {
    _worker.onmessage = _onMessage.toJS;
    _worker.onerror = _onError.toJS;
  }

  final web.Worker _worker;
  final void Function(_ComposeWorker) _onDied;
  final Map<int, (String, Completer<JSObject?>)> _pending = {};
  int _nextId = 1; // the pdfrx worker ignores falsy ids
  Object? _death;

  bool get isDead => _death != null;

  /// Resolves with the `result` object; fails with PdfIoException (engineUnavailable for
  /// an incompatible or missing extension, exportFailed otherwise).
  Future<JSObject?> request(
    String command,
    JSObject parameters, {
    List<JSObject> transfer = const [],
  }) {
    final death = _death;
    if (death != null) {
      return Future.error(
        PdfIoException(
          PdfErrorCode.exportFailed,
          detail: 'compose worker stopped: $death',
          cause: death,
        ),
      );
    }
    final id = _nextId++;
    final completer = Completer<JSObject?>();
    _pending[id] = (command, completer);
    final message = JSObject()
      ..setProperty('id'.toJS, id.toJS)
      ..setProperty('command'.toJS, command.toJS)
      ..setProperty('parameters'.toJS, parameters);
    if (transfer.isEmpty) {
      _worker.postMessage(message);
    } else {
      _worker.postMessage(message, transfer.toJS);
    }
    return completer.future;
  }

  void terminate(Object reason) {
    if (_death != null) return;
    _death = reason;
    _worker.terminate();
    final pending = _pending.values.toList();
    _pending.clear();
    for (final (command, completer) in pending) {
      completer.completeError(
        PdfIoException(
          PdfErrorCode.exportFailed,
          detail: 'compose worker stopped during $command: $reason',
          cause: reason,
        ),
      );
    }
    _onDied(this);
  }

  void _onMessage(web.MessageEvent event) {
    final data = event.data;
    if (data == null || !data.isA<JSObject>()) return;
    final object = data as JSObject;
    final id = object.getProperty<JSAny?>('id'.toJS);
    // {type: 'ready' | 'error' | 'callback'} carry no id; the init request answers too.
    if (id == null || !id.isA<JSNumber>()) return;
    final entry = _pending.remove((id as JSNumber).toDartInt);
    if (entry == null) return;
    final (command, completer) = entry;
    final status = object.getProperty<JSAny?>('status'.toJS);
    if (status != null &&
        status.isA<JSString>() &&
        (status as JSString).toDart == 'success') {
      final result = object.getProperty<JSAny?>('result'.toJS);
      completer.complete(
        result != null && result.isA<JSObject>() ? result as JSObject : null,
      );
      return;
    }
    final error = object.getProperty<JSAny?>('error'.toJS);
    final stack = error != null && error.isA<JSString>()
        ? (error as JSString).toDart
        : 'unknown error';
    final failure = _WorkerError(stack);
    final engine =
        stack.contains(_incompatible) ||
        (command.startsWith('pdfioCompose') &&
            stack.contains('is not a function'));
    completer.completeError(
      PdfIoException(
        engine ? PdfErrorCode.engineUnavailable : PdfErrorCode.exportFailed,
        detail: engine && !stack.contains(_incompatible)
            ? '$_incompatible: ${failure.message}'
            : failure.message,
        cause: failure,
      ),
    );
  }

  void _onError(web.Event event) {
    final message = event.isA<web.ErrorEvent>()
        ? (event as web.ErrorEvent).message
        : event.type;
    terminate(_WorkerError('worker error: $message'));
  }
}
