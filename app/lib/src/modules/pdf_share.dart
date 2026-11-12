/// The native app's PDF share (공유 on pdf_io's result sheet — pdfShareFilesProvider).
/// pdf_io may not depend on a plugin (contract 7.4.1, workspace rule R16), so the share
/// plugin (package:share_plus) is the app's; only `pdf_share_native.dart` imports it
/// (workspace rule R4 `native_only_imports`). The web build gets the stub (null — the web
/// sink shares through navigator.share itself).
library;

export 'pdf_share_stub.dart'
    if (dart.library.io) 'pdf_share_native.dart'
    show platformPdfShare;
