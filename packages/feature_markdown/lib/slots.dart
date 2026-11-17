/// The slots of the MD 문서 screen that the app shell overrides (08-markdown 12.2,
/// C217M-15). No parser and no screen code here: the app imports this file eagerly while
/// `feature_markdown.dart` is deferred on the web.
library;

export 'src/slots_impl.dart'
    show
        MarkdownExportAction,
        markdownExportActionProvider,
        MarkdownOpenLinkAction,
        markdownOpenLinkProvider;
