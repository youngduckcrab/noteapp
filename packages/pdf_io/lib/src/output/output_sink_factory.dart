// lib/src/output/output_sink_factory.dart (conditional export, 06-pdf 4.10, 6.15) — only
// declares createPlatformOutputSink:
//
//   PdfOutputSink createPlatformOutputSink();     // web: browser sink; others: unsupported
export 'output_sink_stub.dart'
    if (dart.library.js_interop) 'output_sink_browser.dart';
