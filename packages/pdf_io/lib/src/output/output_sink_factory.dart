// lib/src/output/output_sink_factory.dart (conditional export, 06-pdf 4.10, 6.15) — only
// declares createPlatformOutputSink:
//
//   /// web: browser sink; native: save dialog + the app's share; others: unsupported
//   PdfOutputSink createPlatformOutputSink({PdfShareFiles? share});
export 'output_sink_stub.dart'
    if (dart.library.js_interop) 'output_sink_browser.dart'
    if (dart.library.io) 'output_sink_native.dart';
