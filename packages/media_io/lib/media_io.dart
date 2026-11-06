/// Recording, playback and image import services (web-safe entry point).
///
/// Owned by PDF (docs/plans/m5-7/06-pdf.md). Public API = contract 00-overview
/// 7.2.12 — exactly its seven names (06-pdf 4.2.6, checked by
/// test/contract/api_surface_test.dart; integration check R14 compares it with
/// the other packages). Services, engines and error types stay internal: other
/// areas use CORE's audio ports. Web-safe.
library;

export 'src/config.dart' show MediaIoConfig;
export 'src/dev/dev_overlay_lines.dart' show mediaDevOverlayLinesProvider;
export 'src/image/image_import.dart'
    show supportedImageSources, importImageForNote;
export 'src/init.dart' show initializeMediaIo, mediaIoOverrides;
export 'src/ui/recording_panel.dart' show RecordingPanel;
