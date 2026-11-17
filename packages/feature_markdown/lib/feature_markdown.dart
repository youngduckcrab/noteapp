/// MD 문서 screen: the rendered view (보기) and the source editor (편집) of a markdown
/// document (MD area, docs/plans/m5-7/08-markdown.md 8 and 12.2; contract 00-overview 7.9
/// v2.17-md C217M-14).
///
/// Public API = [MarkdownScreen] and [MarkdownKeys]; everything under `src/` is private.
/// This entry point pulls in the markdown parser, so the app imports it `deferred` (web
/// budget, 08-markdown 17) and eagerly imports only `package:feature_markdown/slots.dart`.
library;

export 'src/markdown_keys.dart' show MarkdownKeys;
export 'src/markdown_screen.dart' show MarkdownScreen;
