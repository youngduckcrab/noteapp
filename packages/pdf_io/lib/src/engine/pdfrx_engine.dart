// lib/src/engine/pdfrx_engine.dart — 06-pdf 4.3. The only pdf_io file (with init.dart and
// compose/compose_backend_native.dart) that imports package:pdfrx, always `as rx` (3).
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart' as rx;

import '../config.dart';
import '../errors.dart';
import 'page_info.dart';
import 'pdf_engine.dart';

/// Production engine over pdfrx 2.11.0. Process-wide singleton (init is global in pdfrx).
final class PdfrxEngine implements PdfEngine {
  factory PdfrxEngine.shared() => _shared;

  PdfrxEngine._();

  static final PdfrxEngine _shared = PdfrxEngine._();

  bool _initialized = false;
  Future<void>? _initializing;

  /// Applies config before the first ensureInitialized(); later calls are ignored.
  ///
  /// Sets the pdfrx wasm module URL (web; null keeps the pdfrx default
  /// 'assets/packages/pdfrx/assets/', which pdfrx resolves against document.baseURI).
  void configure(PdfIoConfig config) {
    if (_initialized || _initializing != null) return;
    final url = config.pdfiumWasmModulesUrl;
    if (url != null) rx.Pdfrx.pdfiumWasmModulesUrl = url;
  }

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await rx.pdfrxFlutterInitialize();
      _initialized = true;
    } on Object catch (e) {
      // A later call tries again (e.g. the wasm download failed while offline).
      throw PdfIoException(
        PdfErrorCode.engineUnavailable,
        detail: 'pdfrx initialization failed',
        cause: e,
      );
    } finally {
      _initializing = null;
    }
  }

  @override
  Future<PdfEngineDocument> open(
    Uint8List bytes, {
    required String sourceName,
    String fileName = '',
    PdfPasswordCallback? onPassword,
    int maxPasswordAttempts = 5,
    bool transferOwnership = false,
  }) async {
    if (!hasPdfMagic(bytes)) {
      throw const PdfIoException(
        PdfErrorCode.notPdf,
        detail: "no '%PDF-' in the first 1024 bytes",
      );
    }
    // Before openData: with transferOwnership the web may detach [bytes].
    final declaresEncryption = _declaresEncryption(bytes);
    await ensureInitialized();
    var attempts = 0;
    String? lastPassword;
    Future<String?> provide() async {
      attempts++;
      if (onPassword == null || attempts > maxPasswordAttempts) return null;
      lastPassword = await onPassword(
        PdfPasswordRequest(fileName: fileName, attempt: attempts),
      );
      return lastPassword;
    }

    final rx.PdfDocument doc;
    try {
      doc = await rx.PdfDocument.openData(
        bytes,
        sourceName: sourceName,
        passwordProvider: provide,
        allowDataOwnershipTransfer: transferOwnership,
      );
    } on rx.PdfPasswordException catch (e) {
      throw PdfIoException(
        PdfErrorCode.passwordCancelled,
        detail: 'password not given after $attempts request(s)',
        cause: e,
      );
    } on PdfIoException {
      rethrow;
    } on Object catch (e) {
      throw PdfIoException(
        PdfErrorCode.corrupt,
        detail: 'PDFium could not open $sourceName',
        cause: e,
      );
    }
    final password = lastPassword;
    final usedPassword =
        attempts > 0 && password != null && password.isNotEmpty;
    return _PdfrxDocument(
      doc,
      sourceName,
      PdfDocumentInfo(
        pages: [
          for (final page in doc.pages)
            PdfPageInfo(
              index: page.pageNumber - 1,
              width: page.width,
              height: page.height,
              rotationQuarterTurns: page.rotation.index,
            ),
        ],
        isEncrypted: doc.isEncrypted || usedPassword || declaresEncryption,
        usedPassword: usedPassword,
      ),
    );
  }
}

/// pdfrx 2.11.0 web reports isEncrypted only for a non-negative /P (it reads
/// FPDF_GetDocPermissions as a signed int), but real PDFs set the high /P bits. So an
/// '/Encrypt' key in the trailer areas (first and last 64 KiB: classic trailer, xref
/// stream, linearized first page) also counts.
bool _declaresEncryption(Uint8List bytes) {
  const window = 64 * 1024;
  const key = [0x2F, 0x45, 0x6E, 0x63, 0x72, 0x79, 0x70, 0x74]; // /Encrypt
  bool find(int from, int to) {
    outer:
    for (var i = from; i + key.length <= to; i++) {
      for (var j = 0; j < key.length; j++) {
        if (bytes[i + j] != key[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  if (bytes.length <= 2 * window) return find(0, bytes.length);
  return find(0, window) || find(bytes.length - window, bytes.length);
}

final class _PdfrxDocument implements PdfEngineDocument {
  _PdfrxDocument(this._doc, this.sourceName, this.info);

  final rx.PdfDocument _doc;

  @override
  final String sourceName;

  @override
  final PdfDocumentInfo info;

  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  rx.PdfPage _page(int pageIndex) {
    if (_disposed) {
      throw StateError('PdfEngineDocument $sourceName is disposed');
    }
    RangeError.checkValidIndex(pageIndex, info.pages, 'pageIndex');
    return _doc.pages[pageIndex];
  }

  @override
  Future<ui.Image?> render(
    PdfRenderRequest request, {
    PdfRenderCancelToken? cancelToken,
  }) async {
    if (_disposed || (cancelToken?.isCancelled ?? false)) return null;
    final page = _page(request.pageIndex);
    final pageInfo = info.pages[request.pageIndex];
    final (fullWidth, fullHeight) = request.fullPixelSize(pageInfo);
    final region = request.region ?? PdfPixelRect(0, 0, fullWidth, fullHeight);
    if (region.isEmpty) return null;
    final rxToken = cancelToken == null ? null : page.createCancellationToken();
    if (cancelToken != null && rxToken != null) {
      whenRenderCancelled(cancelToken, rxToken.cancel);
    }
    final ui.Image? image;
    try {
      image = await page.renderForDisplay(
        x: region.left,
        y: region.top,
        width: region.width,
        height: region.height,
        fullWidth: pageInfo.width * request.scale,
        fullHeight: pageInfo.height * request.scale,
        backgroundColor: request.backgroundArgb,
        cancellationToken: rxToken,
        priority: switch (request.priority) {
          PdfRenderPriority.high => rx.PdfPageRenderPriority.high,
          PdfRenderPriority.normal => rx.PdfPageRenderPriority.normal,
          PdfRenderPriority.low => rx.PdfPageRenderPriority.low,
        },
      );
    } on Object catch (e) {
      if (cancelToken?.isCancelled ?? false) return null;
      throw PdfIoException(
        PdfErrorCode.corrupt,
        detail: 'render failed: page ${request.pageIndex} of $sourceName',
        cause: e,
      );
    }
    if (image != null && ((cancelToken?.isCancelled ?? false) || _disposed)) {
      image.dispose();
      return null;
    }
    return image;
  }

  @override
  Future<PdfPageTextData> loadText(int pageIndex) async {
    final page = _page(pageIndex);
    final raw = await page.loadText();
    if (raw == null) {
      return PdfPageTextData(
        pageIndex: pageIndex,
        text: '',
        charRects: const [],
      );
    }
    final text = raw.fullText;
    final rects = <ui.Rect>[];
    // pdfrx gives one rect per PDFium char; a char outside the BMP is two UTF-16 units.
    var charIndex = 0;
    for (final rune in text.runes) {
      final rect = charIndex < raw.charRects.length
          ? _toDisplay(raw.charRects[charIndex], page)
          : ui.Rect.zero;
      rects.add(rect);
      if (rune > 0xFFFF) rects.add(rect);
      charIndex++;
    }
    return PdfPageTextData(
      pageIndex: pageIndex,
      text: text,
      charRects: List.unmodifiable(rects),
    );
  }

  /// PDF space (y up, CropBox origin) → displayed page pt (y down, /Rotate applied).
  static ui.Rect _toDisplay(rx.PdfRect rect, rx.PdfPage page) {
    if (rect.left == rect.right && rect.top == rect.bottom) return ui.Rect.zero;
    return rect.toRect(page: page);
  }

  @override
  Future<Uint8List> encodeWithoutSecurity() async {
    if (_disposed) {
      throw StateError('PdfEngineDocument $sourceName is disposed');
    }
    try {
      return await _doc.encodePdf(removeSecurity: true);
    } on Object catch (e) {
      throw PdfIoException(
        PdfErrorCode.corrupt,
        detail: 'could not re-encode $sourceName without security',
        cause: e,
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _doc.dispose();
  }
}
