/// Library screen: folder tree, note list, trash, search, create dialogs.
///
/// Owned by LIBRARY (docs/plans/05-library.md 4.1, docs/plans/m5-7/05-library.md
/// 4.1). Public API = contract 00-overview 7.2.18 + (2차) m5-7/00-overview
/// 7.2.11 (LibraryOpenNoteAt); everything under `src/` is private.
library;

export 'src/appearance/cover_palette.dart'
    show CoverPalette, coverForegroundFor;
export 'src/appearance/folder_appearance.dart' show FolderIcons, FolderPalette;
export 'src/integration/overrides.dart' show featureLibraryOverrides;
export 'src/integration/pdf_slots.dart'
    show
        LibraryPdfImportAction,
        libraryPdfImportActionProvider,
        LibraryPdfExportAction,
        libraryPdfExportActionProvider;
export 'src/library_screen.dart' show LibraryScreen, LibraryOpenNoteAt;
export 'src/settings/library_settings_section.dart' show LibrarySettingsSection;
