// lib/src/compose/compose_backend_native.dart — VM / native compose backend (FFI
// interpreter on the pdfrx background isolate, 06-pdf 6.11.7). Only this file may import
// dart:ffi / package:ffi / package:pdfium_dart (contract 7.4.3); loaded only through
// compose_backend_factory.dart.
//
// begin / addPages / finish / abort are one PdfrxEntryFunctions.compute call each (V4),
// scheduled as pdfrx background work so on-screen renders go first. The job state (PDFium
// document handles, source buffers) lives in [_composeJobs] of the WORKER isolate. Every
// worker callback is synchronous (pdfrx holds its PDFium gate only around synchronous
// work) and returns an error string instead of throwing, so the cause survives the
// isolate boundary.
//
// (2차, m5-7/06-pdf T22 — 6.2.5, 6.2.6, 6.2.8) image and text ops: a part's fonts are loaded
// into the output document first (FPDFText_LoadFont, closed with FPDFFont_Close before the
// document), JPEG bytes go in as they are (FPDFImageObj_LoadJpegFileInline through an
// FPDF_FILEACCESS whose static m_GetBlock reads the one JPEG being loaded — calls are
// synchronous, so they never overlap), RGBA becomes a BGRA bitmap (BGRx when it has no
// alpha: no SMask), text is UTF-16 in native memory. Several parts of one page each open
// the page, add their objects on top and generate the content (E4). The structural rules of
// checkComposeOps run in the worker before a part is interpreted (a broken part →
// exportFailed, nothing drawn).
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart' as ffi_pkg;
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium;
import 'package:pdfrx/pdfrx.dart' as rx;

import '../config.dart';
import '../engine/pdfrx_engine.dart';
import '../errors.dart';
import '../export/compose_ops_check.dart';
import '../export/compose_plan.dart';
import '../export/vectors.dart';
import 'compose_backend.dart';
import 'compose_layout.dart';

/// Web: dedicated Worker (pdfrx pdfium_worker.js + pdf_io_compose_ext.js), chunk 16 pages.
/// VM/native: FFI interpreter on the pdfrx background isolate, chunk 8 pages. Other: unsupported.
PdfComposeBackend createPlatformComposeBackend(PdfIoConfig config) =>
    NativePdfComposeBackend();

/// Job ids are process-wide: every backend shares the one pdfrx worker isolate.
int _nextComposeJobId = 1;

/// Internal (not exported): the native backend. [ensureEngine] defaults to
/// `PdfrxEngine.shared().ensureInitialized` (pdfrx calls FPDF_InitLibrary; this backend
/// never does).
final class NativePdfComposeBackend implements PdfComposeBackend {
  NativePdfComposeBackend({Future<void> Function()? ensureEngine})
    : _ensureEngine = ensureEngine ?? PdfrxEngine.shared().ensureInitialized;

  final Future<void> Function() _ensureEngine;
  final Set<_NativeComposeJob> _jobs = {};
  bool _disposed = false;

  /// Jobs begun here and not yet finished or aborted.
  int get openJobCount => _jobs.length;

  @override
  bool get isSupported => true;

  @override
  Future<PdfComposeJob> begin(PdfComposePlan plan) async {
    if (_disposed) throw StateError('NativePdfComposeBackend is disposed');
    if (plan.pages.isEmpty) {
      throw ArgumentError.value(plan, 'plan', 'no output pages');
    }
    final pages = plan.encodePages();
    // Programming errors (source index out of range, bad note size) fail here, not in
    // the worker.
    decodeComposePlan(pages, plan.sources.length);
    try {
      await _ensureEngine();
    } on PdfIoException {
      rethrow;
    } on Object catch (e) {
      throw PdfIoException(
        PdfErrorCode.engineUnavailable,
        detail: 'pdfrx initialization failed',
        cause: e,
      );
    }
    final jobId = _nextComposeJobId++;
    final result = await _run(_composeBegin, (
      jobId: jobId,
      modulePath: rx.Pdfrx.pdfiumModulePath,
      sources: TransferableTypedData.fromList([
        for (final source in plan.sources) source.bytes,
      ]),
      sourceLengths: [
        for (final source in plan.sources) source.bytes.lengthInBytes,
      ],
      pages: pages,
    ));
    _throwIfError(result.error);
    if (_disposed) {
      // dispose() ran while the worker was loading: nothing may stay open.
      await _run(_composeAbort, jobId);
      throw StateError('NativePdfComposeBackend is disposed');
    }
    final job = _NativeComposeJob(this, jobId, result.pageCount);
    _jobs.add(job);
    return job;
  }

  /// Aborts the jobs still open; later [begin] calls throw StateError.
  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final job in _jobs.toList()) {
      await job.abort();
    }
  }
}

/// Live jobs in the pdfrx worker isolate (all backends). Test hook for 'abort frees the
/// job' (06-pdf 8 T13): the size of the worker's job map.
Future<int> debugNativeComposeJobCount() =>
    _run(_composeJobCount, null, background: false);

enum _JobPhase { open, finishing, closed }

final class _NativeComposeJob implements PdfComposeJob {
  _NativeComposeJob(this._backend, this._jobId, this._pageCount);

  final NativePdfComposeBackend _backend;
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
    // 6.2.8: image and font bytes cross the isolate boundary as TransferableTypedData
    // (one copy here — the export service counts it as `copy` around this call).
    final call = _run(_composeAddPages, (
      jobId: _jobId,
      pages: [
        for (final page in work)
          (
            outputIndex: page.outputIndex,
            verbs: page.verbs,
            coords: page.coords,
            paints: page.paints,
            images: [for (final image in page.images) _imageMessage(image)],
            texts: page.texts,
            fonts: [
              for (final MapEntry(:key, :value) in page.fonts.entries)
                (id: key, bytes: TransferableTypedData.fromList([value])),
            ],
          ),
      ],
    ));
    _pending = call.then((_) {}, onError: (Object _) {});
    _throwIfError(await call);
  }

  @override
  Future<Uint8List> finish() {
    _checkOpen('finish');
    _phase = _JobPhase.finishing;
    return _finishing = () async {
      try {
        final result = await _run(_composeFinish, _jobId);
        _throwIfError(result.error);
        return result.bytes!.materialize().asUint8List();
      } finally {
        _phase = _JobPhase.closed;
        _backend._jobs.remove(this);
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
        _backend._jobs.remove(this);
        // The worker runs calls in order; waiting keeps 'abort done' = 'memory freed'.
        await _pending;
        await _run(_composeAbort, _jobId);
    }
  }
}

/// One compute call on the pdfrx worker, as background work (lower priority than the
/// on-screen renders, 6.11.7). Worker failures outside the callbacks' own error strings
/// (isolate gone, unsendable value) become exportFailed.
Future<R> _run<M, R>(
  R Function(M message) callback,
  M message, {
  bool background = true,
}) async {
  Future<R> call() =>
      rx.PdfrxEntryFunctions.instance.compute(callback, message);
  try {
    return background ? await rx.Pdfrx.runAsBackgroundWork(call) : await call();
  } on PdfIoException {
    rethrow;
  } on Object catch (e) {
    throw PdfIoException(
      PdfErrorCode.exportFailed,
      detail: 'compose worker call failed',
      cause: e,
    );
  }
}

/// Worker error strings: `engine: …` (the bindings could not load) or `export: …`.
void _throwIfError(String? error) {
  if (error == null) return;
  final engine = error.startsWith(_engineError);
  throw PdfIoException(
    engine ? PdfErrorCode.engineUnavailable : PdfErrorCode.exportFailed,
    detail: error.substring((engine ? _engineError : _exportError).length),
  );
}

const String _engineError = 'engine: ';
const String _exportError = 'export: ';

// ---------------------------------------------------------------------------------------
// Worker isolate side. Everything below runs inside PdfrxEntryFunctions.compute.

typedef _BeginMessage = ({
  int jobId,
  String? modulePath,
  TransferableTypedData sources,
  List<int> sourceLengths,
  Float64List pages,
});

typedef _PageOpsMessage = ({
  int outputIndex,
  Uint8List verbs,
  Float32List coords,
  Float32List paints,
  List<_ImageMessage> images,
  List<String> texts,
  List<_FontMessage> fonts,
});

/// [jpeg]: JPEG file bytes; otherwise straight RGBA8888, top row first.
typedef _ImageMessage = ({
  bool jpeg,
  int width,
  int height,
  bool hasAlpha,
  TransferableTypedData bytes,
});

typedef _FontMessage = ({int id, TransferableTypedData bytes});

_ImageMessage _imageMessage(PdfImageData image) => switch (image) {
  PdfJpegData(:final bytes, :final width, :final height) => (
    jpeg: true,
    width: width,
    height: height,
    hasAlpha: false,
    bytes: TransferableTypedData.fromList([bytes]),
  ),
  PdfRgbaData(:final rgba, :final width, :final height, :final hasAlpha) => (
    jpeg: false,
    width: width,
    height: height,
    hasAlpha: hasAlpha,
    bytes: TransferableTypedData.fromList([rgba]),
  ),
};

typedef _AddPagesMessage = ({int jobId, List<_PageOpsMessage> pages});

final class _ComposeFailure implements Exception {
  _ComposeFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

final class _ComposeJobState {
  _ComposeJobState(this.lib, this.document, this.rows);
  final pdfium.PDFium lib;
  final pdfium.FPDF_DOCUMENT document;
  final List<PdfComposePlanRow> rows;
  final List<pdfium.FPDF_DOCUMENT> sources = [];
  final List<ffi.Pointer<ffi.Uint8>> buffers = [];

  /// (2차) Fonts loaded into [document] by earlier parts (fontId → handle).
  final Map<int, pdfium.FPDF_FONT> fonts = {};

  /// Closes the fonts (before their document — a font points at it), every document, then
  /// frees the source buffers (PDFium reads them until the source document is closed).
  void release() {
    for (final font in fonts.values) {
      lib.FPDFFont_Close(font);
    }
    fonts.clear();
    lib.FPDF_CloseDocument(document);
    for (final source in sources) {
      lib.FPDF_CloseDocument(source);
    }
    sources.clear();
    for (final buffer in buffers) {
      ffi_pkg.malloc.free(buffer);
    }
    buffers.clear();
  }
}

/// Worker isolate: job id → state.
final Map<int, _ComposeJobState> _composeJobs = {};

/// Worker isolate: the bindings (pdfrx already loaded and initialized the same module in
/// this process; the path comes in the message because statics are per isolate).
pdfium.PDFium? _workerPdfium;

pdfium.PDFium _bindings(String? modulePath) =>
    _workerPdfium ??= pdfium.getPdfium(modulePath: modulePath);

int _composeJobCount(Object? _) => _composeJobs.length;

({String? error, int pageCount}) _composeBegin(_BeginMessage message) {
  final pdfium.PDFium lib;
  try {
    lib = _bindings(message.modulePath);
  } on Object catch (e) {
    return (error: '$_engineError$e', pageCount: 0);
  }
  _ComposeJobState? job;
  try {
    final sourceCount = message.sourceLengths.length;
    final rows = decodeComposePlan(message.pages, sourceCount);
    final all = message.sources.materialize();
    final document = lib.FPDF_CreateNewDocument();
    if (document == ffi.nullptr) {
      throw _ComposeFailure('FPDF_CreateNewDocument failed');
    }
    final state = job = _ComposeJobState(lib, document, rows);
    // 6.11.4 step 1: each source into engine memory (FPDF_LoadMemDocument keeps reading it).
    var offset = 0;
    for (var s = 0; s < sourceCount; s++) {
      final length = message.sourceLengths[s];
      final buffer = ffi_pkg.malloc<ffi.Uint8>(length == 0 ? 1 : length);
      state.buffers.add(buffer);
      buffer.asTypedList(length).setAll(0, all.asUint8List(offset, length));
      offset += length;
      final source = lib.FPDF_LoadMemDocument64(
        buffer.cast(),
        length,
        ffi.nullptr,
      );
      if (source == ffi.nullptr) {
        throw _ComposeFailure(
          'source $s: FPDF_LoadMemDocument error ${lib.FPDF_GetLastError()}',
        );
      }
      state.sources.add(source);
    }
    final layout = PdfComposeLayout.of(rows, sourceCount);
    // Step 3: one import call per source (V7: shared resources are copied once).
    for (var s = 0; s < sourceCount; s++) {
      final indexes = layout.imports[s];
      if (indexes.isEmpty) continue;
      final count = lib.FPDF_GetPageCount(state.sources[s]);
      for (final index in indexes) {
        if (index >= count) {
          throw _ComposeFailure(
            'source $s: pdf page $index not in 0..${count - 1}',
          );
        }
      }
      ffi_pkg.using((arena) {
        final list = arena<ffi.Int>(indexes.length);
        for (var i = 0; i < indexes.length; i++) {
          list[i] = indexes[i];
        }
        final ok = lib.FPDF_ImportPagesByIndex(
          document,
          state.sources[s],
          list,
          indexes.length,
          lib.FPDF_GetPageCount(document),
        );
        if (ok == 0) throw _ComposeFailure('source $s: import failed');
      });
    }
    // Step 4: source pages into output order (several sources only).
    for (final (from, to) in layout.moves) {
      ffi_pkg.using((arena) {
        final list = arena<ffi.Int>();
        list.value = from;
        if (lib.FPDF_MovePages(document, list, 1, to) == 0) {
          throw _ComposeFailure('move $from → $to failed');
        }
      });
    }
    // Step 5: blank pages at their final indexes, ascending.
    for (final index in layout.blanks) {
      final row = rows[index];
      final page = lib.FPDFPage_New(
        document,
        index,
        row.noteWidth,
        row.noteHeight,
      );
      if (page == ffi.nullptr) throw _ComposeFailure('blank page $index');
      lib.FPDF_ClosePage(page);
    }
    // Step 6.
    final pageCount = lib.FPDF_GetPageCount(document);
    if (pageCount != rows.length) {
      throw _ComposeFailure('$pageCount pages, plan has ${rows.length}');
    }
    _composeJobs[message.jobId] = state;
    return (error: null, pageCount: pageCount);
  } on Object catch (e) {
    job?.release();
    return (error: '$_exportError$e', pageCount: 0);
  }
}

String? _composeAddPages(_AddPagesMessage message) {
  final job = _composeJobs[message.jobId];
  if (job == null) return '${_exportError}job ${message.jobId} is not open';
  try {
    for (final ops in message.pages) {
      _interpretPage(job, ops);
    }
    return null;
  } on Object catch (e) {
    return '$_exportError$e';
  }
}

/// 6.11.5 interpreter for one output page; (2차) one part of it (6.2.6): its fonts first,
/// then its ops on top of what the page already has.
void _interpretPage(_ComposeJobState job, _PageOpsMessage message) {
  final lib = job.lib;
  final ops = _materialize(message);
  try {
    checkComposeOps(ops, loadedFonts: job.fonts.keys.toSet());
  } on ArgumentError catch (e) {
    throw _ComposeFailure('page ${ops.outputIndex}: ${e.message} (${e.name})');
  }
  for (final MapEntry(key: id, value: bytes) in ops.fonts.entries) {
    job.fonts[id] = _loadFont(job, id, bytes);
  }
  final row = job.rows[ops.outputIndex];
  final page = lib.FPDF_LoadPage(job.document, ops.outputIndex);
  if (page == ffi.nullptr) {
    throw _ComposeFailure('FPDF_LoadPage ${ops.outputIndex} failed');
  }
  pdfium.FPDF_PAGEOBJECT? object;
  final multiply = 'Multiply'.toNativeUtf8();
  try {
    final m = _pageBox(
      lib,
      page,
    ).noteToUser(ui.Size(row.noteWidth, row.noteHeight));
    final verbs = ops.verbs, coords = ops.coords, paints = ops.paints;
    var c = 0;
    for (var v = 0; v < verbs.length; v++) {
      switch (verbs[v]) {
        case PdfComposeOpcodes.moveTo:
          final x = coords[c], y = coords[c + 1];
          c += 2;
          final current = object;
          if (current != null) {
            lib.FPDFPath_MoveTo(current, x, y);
          } else {
            final created = lib.FPDFPageObj_CreateNewPath(x, y);
            if (created == ffi.nullptr) {
              throw _ComposeFailure('FPDFPageObj_CreateNewPath failed');
            }
            object = created;
          }
        case PdfComposeOpcodes.lineTo:
          lib.FPDFPath_LineTo(_open(object, v), coords[c], coords[c + 1]);
          c += 2;
        case PdfComposeOpcodes.cubicTo:
          lib.FPDFPath_BezierTo(
            _open(object, v),
            coords[c],
            coords[c + 1],
            coords[c + 2],
            coords[c + 3],
            coords[c + 4],
            coords[c + 5],
          );
          c += 6;
        case PdfComposeOpcodes.close:
          lib.FPDFPath_Close(_open(object, v));
        case PdfComposeOpcodes.endObject:
          final path = _open(object, v);
          final paint = coords[c].round();
          c += 1;
          final p = paint * PdfComposeOpcodes.paintStride;
          if (paint < 0 || p + PdfComposeOpcodes.paintStride > paints.length) {
            throw _ComposeFailure('verb $v: paint $paint missing');
          }
          _applyPaint(lib, path, paints, p, multiply);
          lib.FPDFPageObj_Transform(path, m[0], m[1], m[2], m[3], m[4], m[5]);
          object = null;
          if (lib.FPDFPage_InsertObject(page, path) == 0) {
            lib.FPDFPageObj_Destroy(path);
            throw _ComposeFailure('FPDFPage_InsertObject failed');
          }
        case PdfComposeOpcodes.image:
          final image = ops.images[coords[c].toInt()];
          final placed = _imageObject(job, page, image, v);
          _place(lib, page, placed, coords, c + 1, m);
          c += PdfComposeOpcodes.imageArgs;
        case PdfComposeOpcodes.text:
          final placed = _textObject(job, ops, coords, c, v);
          _applyFill(lib, placed, coords, c + 3);
          _place(lib, page, placed, coords, c + 7, m);
          c += PdfComposeOpcodes.textArgs;
        default:
          throw _ComposeFailure('verb $v: unknown opcode ${verbs[v]}');
      }
    }
    if (object != null) throw _ComposeFailure('ops end inside an object');
    if (lib.FPDFPage_GenerateContent(page) == 0) {
      throw _ComposeFailure('FPDFPage_GenerateContent ${ops.outputIndex}');
    }
  } finally {
    // An object not inserted yet is still ours.
    final dangling = object;
    if (dangling != null) lib.FPDFPageObj_Destroy(dangling);
    ffi_pkg.malloc.free(multiply);
    lib.FPDF_ClosePage(page);
  }
}

/// The worker-side PdfComposePageOps of [message] (bytes materialized once).
PdfComposePageOps _materialize(_PageOpsMessage message) => PdfComposePageOps(
  outputIndex: message.outputIndex,
  verbs: message.verbs,
  coords: message.coords,
  paints: message.paints,
  images: [
    for (final image in message.images)
      if (image.jpeg)
        PdfJpegData(
          image.bytes.materialize().asUint8List(),
          width: image.width,
          height: image.height,
        )
      else
        PdfRgbaData(
          image.bytes.materialize().asUint8List(),
          width: image.width,
          height: image.height,
          hasAlpha: image.hasAlpha,
        ),
  ],
  texts: message.texts,
  fonts: {
    for (final font in message.fonts)
      font.id: font.bytes.materialize().asUint8List(),
  },
);

/// 6.2.5: FPDFText_LoadFont(TrueType, cid) — PDFium copies the data, the buffer is freed here.
pdfium.FPDF_FONT _loadFont(_ComposeJobState job, int id, Uint8List bytes) {
  final buffer = ffi_pkg.malloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
  try {
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    const trueType = 2; // FPDF_FONT_TRUETYPE
    final font = job.lib.FPDFText_LoadFont(
      job.document,
      buffer,
      bytes.length,
      trueType,
      1, // cid: Hangul needs a CID font
    );
    if (font == ffi.nullptr) {
      throw _ComposeFailure('font $id: FPDFText_LoadFont failed');
    }
    return font;
  } finally {
    ffi_pkg.malloc.free(buffer);
  }
}

/// A new image object holding [image] (not inserted yet — the caller owns it).
pdfium.FPDF_PAGEOBJECT _imageObject(
  _ComposeJobState job,
  pdfium.FPDF_PAGE page,
  PdfImageData image,
  int verb,
) {
  final lib = job.lib;
  final object = lib.FPDFPageObj_NewImageObj(job.document);
  if (object == ffi.nullptr) {
    throw _ComposeFailure('verb $verb: FPDFPageObj_NewImageObj failed');
  }
  try {
    final ok = ffi_pkg.using((arena) {
      final pages = arena<pdfium.FPDF_PAGE>()..value = page;
      switch (image) {
        case PdfJpegData(:final bytes):
          final access = arena<pdfium.FPDF_FILEACCESS>();
          access.ref
            ..m_FileLen = bytes.length
            ..m_GetBlock = _jpegGetBlock
            ..m_Param = ffi.nullptr;
          _loadingJpeg = bytes;
          try {
            return lib.FPDFImageObj_LoadJpegFileInline(
              pages,
              1,
              object,
              access,
            );
          } finally {
            _loadingJpeg = null;
          }
        case PdfRgbaData(:final rgba, :final width, :final height):
          return _setBitmap(lib, pages, object, image, rgba, width, height);
      }
    });
    if (ok == 0) {
      throw _ComposeFailure('verb $verb: loading $image into PDFium failed');
    }
    return object;
  } on Object {
    lib.FPDFPageObj_Destroy(object);
    rethrow;
  }
}

/// RGBA → BGRA (BGRx without alpha) in native memory → FPDFImageObj_SetBitmap (PDFium copies).
int _setBitmap(
  pdfium.PDFium lib,
  ffi.Pointer<pdfium.FPDF_PAGE> pages,
  pdfium.FPDF_PAGEOBJECT object,
  PdfRgbaData image,
  Uint8List rgba,
  int width,
  int height,
) {
  final length = width * height * 4;
  if (width <= 0 || height <= 0 || rgba.length != length) {
    throw _ComposeFailure('$image: ${rgba.length} B for $width × $height');
  }
  final buffer = ffi_pkg.malloc<ffi.Uint8>(length);
  try {
    final bgra = buffer.asTypedList(length);
    for (var i = 0; i < length; i += 4) {
      bgra[i] = rgba[i + 2];
      bgra[i + 1] = rgba[i + 1];
      bgra[i + 2] = rgba[i];
      bgra[i + 3] = rgba[i + 3];
    }
    final bitmap = lib.FPDFBitmap_CreateEx(
      width,
      height,
      image.hasAlpha ? pdfium.FPDFBitmap_BGRA : pdfium.FPDFBitmap_BGRx,
      buffer.cast(),
      width * 4,
    );
    if (bitmap == ffi.nullptr) {
      throw _ComposeFailure('FPDFBitmap_CreateEx $width × $height failed');
    }
    try {
      return lib.FPDFImageObj_SetBitmap(pages, 1, object, bitmap);
    } finally {
      lib.FPDFBitmap_Destroy(bitmap);
    }
  } finally {
    ffi_pkg.malloc.free(buffer);
  }
}

/// A new text object for the `text` op at coords[c] (not inserted yet).
pdfium.FPDF_PAGEOBJECT _textObject(
  _ComposeJobState job,
  PdfComposePageOps ops,
  Float32List coords,
  int c,
  int verb,
) {
  final lib = job.lib;
  final text = ops.texts[coords[c].toInt()];
  final font = job.fonts[coords[c + 1].toInt()]!; // checkComposeOps: loaded
  final object = lib.FPDFPageObj_CreateTextObj(
    job.document,
    font,
    coords[c + 2],
  );
  if (object == ffi.nullptr) {
    throw _ComposeFailure('verb $verb: FPDFPageObj_CreateTextObj failed');
  }
  final units = text.codeUnits;
  final wide = ffi_pkg.malloc<ffi.UnsignedShort>(units.length + 1);
  try {
    final list = wide.cast<ffi.Uint16>().asTypedList(units.length + 1);
    list.setAll(0, units);
    list[units.length] = 0;
    if (lib.FPDFText_SetText(object, wide) == 0) {
      throw _ComposeFailure('verb $verb: FPDFText_SetText failed');
    }
    return object;
  } on Object {
    lib.FPDFPageObj_Destroy(object);
    rethrow;
  } finally {
    ffi_pkg.malloc.free(wide);
  }
}

/// Fill color [r, g, b, alpha255] at coords[c].
void _applyFill(
  pdfium.PDFium lib,
  pdfium.FPDF_PAGEOBJECT object,
  Float32List coords,
  int c,
) {
  lib.FPDFPageObj_SetFillColor(
    object,
    coords[c].round(),
    coords[c + 1].round(),
    coords[c + 2].round(),
    coords[c + 3].round(),
  );
}

/// The object's own matrix (image: unit square → note pt; text: text space → note pt) at
/// coords[c..c+5], then note → user [m], then onto [page] (owned by the page afterwards).
void _place(
  pdfium.PDFium lib,
  pdfium.FPDF_PAGE page,
  pdfium.FPDF_PAGEOBJECT object,
  Float32List coords,
  int c,
  List<double> m,
) {
  try {
    lib.FPDFPageObj_Transform(
      object,
      coords[c],
      coords[c + 1],
      coords[c + 2],
      coords[c + 3],
      coords[c + 4],
      coords[c + 5],
    );
    lib.FPDFPageObj_Transform(object, m[0], m[1], m[2], m[3], m[4], m[5]);
    if (lib.FPDFPage_InsertObject(page, object) == 0) {
      throw _ComposeFailure('FPDFPage_InsertObject failed');
    }
  } on Object {
    lib.FPDFPageObj_Destroy(object);
    rethrow;
  }
}

/// Worker isolate: the JPEG FPDFImageObj_LoadJpegFileInline is reading (6.2.8).
Uint8List? _loadingJpeg;

int _readJpegBlock(
  ffi.Pointer<ffi.Void> param,
  int position,
  ffi.Pointer<ffi.UnsignedChar> buffer,
  int size,
) {
  final source = _loadingJpeg;
  if (source == null || position < 0 || position + size > source.length) {
    return 0;
  }
  buffer
      .cast<ffi.Uint8>()
      .asTypedList(size)
      .setRange(0, size, source, position);
  return 1;
}

final ffi.Pointer<
  ffi.NativeFunction<
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.UnsignedLong,
      ffi.Pointer<ffi.UnsignedChar>,
      ffi.UnsignedLong,
    )
  >
>
_jpegGetBlock = ffi.Pointer.fromFunction(_readJpegBlock, 0);

pdfium.FPDF_PAGEOBJECT _open(pdfium.FPDF_PAGEOBJECT? object, int verb) {
  if (object == null) throw _ComposeFailure('verb $verb: no moveTo before it');
  return object;
}

void _applyPaint(
  pdfium.PDFium lib,
  pdfium.FPDF_PAGEOBJECT path,
  Float32List paints,
  int p,
  ffi.Pointer<ffi_pkg.Utf8> multiply,
) {
  final r = paints[p + 1].round(), g = paints[p + 2].round();
  final b = paints[p + 3].round(), a = paints[p + 4].round();
  if (paints[p] == 1) {
    lib.FPDFPageObj_SetStrokeColor(path, r, g, b, a);
    lib.FPDFPageObj_SetStrokeWidth(path, paints[p + 5]);
    lib.FPDFPageObj_SetLineCap(path, paints[p + 6].round());
    lib.FPDFPageObj_SetLineJoin(path, paints[p + 7].round());
    lib.FPDFPath_SetDrawMode(path, 0, 1);
  } else {
    lib.FPDFPageObj_SetFillColor(path, r, g, b, a);
    lib.FPDFPath_SetDrawMode(path, paints[p + 9].round(), 0);
  }
  if (paints[p + 8] == 1) lib.FPDFPageObj_SetBlendMode(path, multiply.cast());
}

/// Rotation and visible box of [page] (6.11.3).
PdfComposePageBox _pageBox(pdfium.PDFium lib, pdfium.FPDF_PAGE page) {
  return ffi_pkg.using((arena) {
    final l = arena<ffi.Float>(), b = arena<ffi.Float>();
    final r = arena<ffi.Float>(), t = arena<ffi.Float>();
    final media = lib.FPDFPage_GetMediaBox(page, l, b, r, t) == 0
        ? null
        : [l.value, b.value, r.value, t.value];
    final crop = lib.FPDFPage_GetCropBox(page, l, b, r, t) == 0
        ? null
        : [l.value, b.value, r.value, t.value];
    return PdfComposePageBox.visible(
      mediaBox: media,
      cropBox: crop,
      rotation: lib.FPDFPage_GetRotation(page),
    );
  });
}

({String? error, TransferableTypedData? bytes}) _composeFinish(int jobId) {
  final job = _composeJobs.remove(jobId);
  if (job == null) {
    return (error: '${_exportError}job $jobId is not open', bytes: null);
  }
  final out = BytesBuilder();
  int write(
    ffi.Pointer<pdfium.FPDF_FILEWRITE> self,
    ffi.Pointer<ffi.Void> data,
    int size,
  ) {
    out.add(data.cast<ffi.Uint8>().asTypedList(size));
    return 1;
  }

  final callable =
      ffi.NativeCallable<
        ffi.Int Function(
          ffi.Pointer<pdfium.FPDF_FILEWRITE>,
          ffi.Pointer<ffi.Void>,
          ffi.UnsignedLong,
        )
      >.isolateLocal(write, exceptionalReturn: 0);
  try {
    return ffi_pkg.using((arena) {
      final writer = arena<pdfium.FPDF_FILEWRITE>();
      writer.ref.version = 1;
      writer.ref.WriteBlock = callable.nativeFunction;
      const noIncremental = 2; // FPDF_NO_INCREMENTAL
      if (job.lib.FPDF_SaveAsCopy(job.document, writer, noIncremental) == 0) {
        return (error: '${_exportError}FPDF_SaveAsCopy failed', bytes: null);
      }
      return (
        error: null,
        bytes: TransferableTypedData.fromList([out.takeBytes()]),
      );
    });
  } on Object catch (e) {
    return (error: '$_exportError$e', bytes: null);
  } finally {
    callable.close();
    job.release();
  }
}

void _composeAbort(int jobId) {
  _composeJobs.remove(jobId)?.release();
}
