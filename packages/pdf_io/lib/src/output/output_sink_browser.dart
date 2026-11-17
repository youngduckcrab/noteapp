// lib/src/output/output_sink_browser.dart — web output sink (Web Share API, download, new
// tab — 06-pdf 6.12). Only *_browser.dart files may import dart:js_interop / package:web
// (contract 7.4.3); loaded only through output_sink_factory.dart.
//
// share: navigator.canShare({files}) with every result as a File('application/pdf'), then
// navigator.share — AbortError → dismissedByUser, NotAllowedError → needsUserGesture (the
// tap's user activation expired), anything else → failed. download: a Blob URL on a hidden
// <a download="name"> that is clicked and removed. openInNewTab: window.open(blobUrl,
// '_blank') — null (popup blocked) → needsUserGesture. Blob URLs are revoked after
// [BrowserPdfOutputSink.revokeDelay] (5 minutes). deliver calls the browser API before it
// returns (no await first): the result sheet calls it from the tap handler (Safari user
// activation, 6.12).
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../export/export_types.dart';
import 'document_output.dart';
import 'pdf_output_sink.dart';

/// (v2.17-md) The outcome of a failed navigator.share (shared with DocumentFileOutput):
/// AbortError → dismissedByUser, NotAllowedError → needsUserGesture, else failed.
PdfOutputOutcome browserShareFailure(Object error) {
  if (!error.isA<web.DOMException>()) return PdfOutputOutcome.failed;
  return switch ((error as web.DOMException).name) {
    'AbortError' => PdfOutputOutcome.dismissedByUser,
    'NotAllowedError' => PdfOutputOutcome.needsUserGesture,
    _ => PdfOutputOutcome.failed,
  };
}

/// (v2.17-md) A download of [url] as [fileName]: a hidden <a download> clicked and
/// removed (shared with DocumentFileOutput).
PdfOutputOutcome browserDownload(String url, String fileName) {
  final body = web.document.body;
  if (body == null) return PdfOutputOutcome.failed;
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  body.append(anchor);
  anchor.click();
  anchor.remove();
  return PdfOutputOutcome.done;
}

/// web: browser sink; native: save dialog + the app's share; others: unsupported.
/// [share] is for the native sink only (the web shares through navigator.share).
PdfOutputSink createPlatformOutputSink({PdfShareFiles? share}) =>
    BrowserPdfOutputSink();

/// Internal (not exported): the browser sink. [navigator] and [openWindow] are replaced by
/// the browser tests only (a fake navigator records canShare / share; a fake opener stands
/// for window.open).
final class BrowserPdfOutputSink implements PdfOutputSink {
  BrowserPdfOutputSink({
    web.Navigator? navigator,
    web.Window? Function(String url)? openWindow,
    this.revokeDelay = const Duration(minutes: 5),
  }) : _navigator = navigator ?? web.window.navigator,
       _openWindow = openWindow ?? _openBlank;

  final web.Navigator _navigator;
  final web.Window? Function(String url) _openWindow;

  /// How long a Blob URL handed to a download or a new tab stays valid (6.12).
  final Duration revokeDelay;

  /// One File per result, made once (a File copies the bytes; the result sheet asks for the
  /// available actions on every build).
  final Expando<web.File> _files = Expando<web.File>('pdf_io output file');

  static web.Window? _openBlank(String url) => web.window.open(url, '_blank');

  web.File _fileOf(PdfExportResult result) => _files[result] ??= web.File(
    <web.BlobPart>[result.bytes.toJS].toJS,
    result.fileName,
    web.FilePropertyBag(type: 'application/pdf'),
  );

  web.ShareData _shareData(List<PdfExportResult> results) => web.ShareData(
    files: <web.File>[for (final r in results) _fileOf(r)].toJS,
    title: results.length == 1
        ? results.single.fileName
        : 'PDF ${results.length}개',
  );

  bool _canShare(List<PdfExportResult> results) {
    // Desktop Chrome on Linux has neither canShare nor share.
    if (!_navigator.has('canShare') || !_navigator.has('share')) return false;
    try {
      return _navigator.canShare(_shareData(results));
    } on Object {
      return false;
    }
  }

  @override
  Set<PdfOutputAction> availableActions(List<PdfExportResult> results) {
    if (results.isEmpty) return const <PdfOutputAction>{};
    return {
      if (_canShare(results)) PdfOutputAction.share,
      if (results.length == 1) ...const {
        PdfOutputAction.download,
        PdfOutputAction.openInNewTab,
      },
    };
  }

  @override
  Future<PdfOutputOutcome> deliver(
    List<PdfExportResult> results,
    PdfOutputAction action,
  ) {
    if (!availableActions(results).contains(action)) {
      throw ArgumentError.value(action, 'action', 'not available');
    }
    return switch (action) {
      PdfOutputAction.share => _share(results),
      PdfOutputAction.download => Future.value(_download(results.single)),
      PdfOutputAction.openInNewTab => Future.value(_open(results.single)),
    };
  }

  Future<PdfOutputOutcome> _share(List<PdfExportResult> results) {
    final JSPromise<JSAny?> promise;
    try {
      promise = _navigator.share(_shareData(results));
    } on Object catch (e) {
      return Future.value(_shareFailure(e));
    }
    return promise.toDart.then(
      (_) => PdfOutputOutcome.done,
      onError: _shareFailure,
    );
  }

  static PdfOutputOutcome _shareFailure(Object error) =>
      browserShareFailure(error);

  String _objectUrl(PdfExportResult result) {
    final url = web.URL.createObjectURL(_fileOf(result));
    Timer(revokeDelay, () => web.URL.revokeObjectURL(url));
    return url;
  }

  PdfOutputOutcome _download(PdfExportResult result) {
    try {
      return browserDownload(_objectUrl(result), result.fileName);
    } on Object {
      return PdfOutputOutcome.failed;
    }
  }

  PdfOutputOutcome _open(PdfExportResult result) {
    try {
      return _openWindow(_objectUrl(result)) == null
          ? PdfOutputOutcome.needsUserGesture
          : PdfOutputOutcome.done;
    } on Object {
      return PdfOutputOutcome.failed;
    }
  }
}

// ---- (v2.17-md, C217M-12) DocumentFileOutput: one file of any type --------------

DocumentFileOutput createPlatformDocumentOutput({DocumentShareFile? share}) =>
    BrowserDocumentOutput();

final class BrowserDocumentOutput implements DocumentFileOutput {
  BrowserDocumentOutput({web.Navigator? navigator})
    : _navigator = navigator ?? web.window.navigator;

  final web.Navigator _navigator;

  web.File _file(DocumentFile f, String type) => web.File(
    <web.BlobPart>[f.bytes.toJS].toJS,
    f.name,
    web.FilePropertyBag(type: type),
  );

  web.ShareData _shareData(DocumentFile f) => web.ShareData(
    files: <web.File>[_file(f, f.shareMimeType)].toJS,
    title: f.name,
  );

  bool _canShare(DocumentFile f) {
    if (!_navigator.has('canShare') || !_navigator.has('share')) return false;
    try {
      return _navigator.canShare(_shareData(f));
    } on Object {
      return false;
    }
  }

  @override
  Set<DocumentOutputAction> availableActions(DocumentFile file) => {
    if (_canShare(file)) DocumentOutputAction.share,
    DocumentOutputAction.save,
  };

  @override
  String labelOf(DocumentOutputAction action) => switch (action) {
    DocumentOutputAction.share => '공유',
    DocumentOutputAction.save => '다운로드',
  };

  @override
  Future<PdfOutputOutcome> deliver(
    DocumentFile file,
    DocumentOutputAction action,
  ) {
    if (!availableActions(file).contains(action)) {
      throw ArgumentError.value(action, 'action', 'not available');
    }
    switch (action) {
      case DocumentOutputAction.share:
        final JSPromise<JSAny?> promise;
        try {
          promise = _navigator.share(_shareData(file));
        } on Object catch (e) {
          return Future.value(browserShareFailure(e));
        }
        return promise.toDart.then(
          (_) => PdfOutputOutcome.done,
          onError: browserShareFailure,
        );
      case DocumentOutputAction.save:
        try {
          final url = web.URL.createObjectURL(_file(file, file.mimeType));
          Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
          return Future.value(browserDownload(url, file.name));
        } on Object {
          return Future.value(PdfOutputOutcome.failed);
        }
    }
  }
}
