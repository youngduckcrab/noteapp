/// (v2.17-md, C217M-12) The native app's share of one file ('.md로 내보내기' › 공유): the
/// share plugin (package:share_plus) is the app's (R16); only `document_share_native.dart`
/// imports it (R4 native_only_imports). The web gets the stub (null — the web output
/// shares through navigator.share itself).
library;

export 'document_share_stub.dart'
    if (dart.library.io) 'document_share_native.dart'
    show platformDocumentShare;
