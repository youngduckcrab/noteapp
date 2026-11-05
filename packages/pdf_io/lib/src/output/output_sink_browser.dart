// lib/src/output/output_sink_browser.dart — web output sink (Web Share API, download, new
// tab — 06-pdf 6.12). Only *_browser.dart files may import dart:js_interop / package:web
// (contract 7.4.3); loaded only through output_sink_factory.dart.
//
// Foundation step B4 (T0): placeholder; the browser sink comes with PDF T16.
import 'pdf_output_sink.dart';

/// web: browser sink; others: unsupported
PdfOutputSink createPlatformOutputSink() =>
    throw UnimplementedError('createPlatformOutputSink (web, PDF T16)');
