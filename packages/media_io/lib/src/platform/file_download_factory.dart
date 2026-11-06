// lib/src/platform/file_download_factory.dart (conditional export, m5-7/06-pdf 6.10.4, 6.18) —
// declares:
//
//   /// Web: Blob + object URL + <a download> (file_download_browser.dart). Else: none
//   /// (file_download_stub.dart → NoFileDownloads).
//   FileDownloads createPlatformFileDownloads();
export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_browser.dart';
