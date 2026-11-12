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
import 'pdf_output_sink.dart';

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

  static PdfOutputOutcome _shareFailure(Object error) {
    if (!error.isA<web.DOMException>()) return PdfOutputOutcome.failed;
    return switch ((error as web.DOMException).name) {
      'AbortError' => PdfOutputOutcome.dismissedByUser,
      'NotAllowedError' => PdfOutputOutcome.needsUserGesture,
      _ => PdfOutputOutcome.failed,
    };
  }

  String _objectUrl(PdfExportResult result) {
    final url = web.URL.createObjectURL(_fileOf(result));
    Timer(revokeDelay, () => web.URL.revokeObjectURL(url));
    return url;
  }

  PdfOutputOutcome _download(PdfExportResult result) {
    final body = web.document.body;
    if (body == null) return PdfOutputOutcome.failed;
    try {
      final anchor = web.HTMLAnchorElement()
        ..href = _objectUrl(result)
        ..download = result.fileName
        ..style.display = 'none';
      body.append(anchor);
      anchor.click();
      anchor.remove();
      return PdfOutputOutcome.done;
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
