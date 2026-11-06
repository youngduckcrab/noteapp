// lib/src/platform/file_download_stub.dart — file_download_factory.dart off the web (m5-7/06-pdf
// 6.10.4, 6.18): no download (native drafts stay in the app support directory and are recovered on
// the next launch). Internal.
import 'file_download.dart';

FileDownloads createPlatformFileDownloads() => const NoFileDownloads();
