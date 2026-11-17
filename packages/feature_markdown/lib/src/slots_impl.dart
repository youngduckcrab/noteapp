// The two slot providers of feature_markdown (08-markdown 10.4 and 8.6, C217M-15).
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// '.md로 내보내기' of the screen's ⋯ menu: save / share [text] byte for byte (UTF-8) under
/// a file name made from [title]. The app owns it (pdf_io file output + share_plus).
typedef MarkdownExportAction = Future<void> Function(
  BuildContext context, {
  required String title,
  required String text,
});

/// null → the menu item is hidden.
final markdownExportActionProvider = Provider<MarkdownExportAction?>(
  (ref) => null,
  name: 'markdownExportActionProvider',
);

/// [외부 앱에서 열기] of the link sheet. Called only after the user chose it, and only for
/// http, https, mailto and tel; returns false when nothing could open the link ('열지
/// 못했어요'). The app owns it (url_launcher).
typedef MarkdownOpenLinkAction = Future<bool> Function(Uri uri);

/// null → the link sheet offers [복사] only.
final markdownOpenLinkProvider = Provider<MarkdownOpenLinkAction?>(
  (ref) => null,
  name: 'markdownOpenLinkProvider',
);
