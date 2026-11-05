/// Note editor screen: writing surface, input routing, toolbar, pen settings,
/// page panel and developer overlay.
///
/// Owned by EDITOR (docs/plans/04-editor.md 4.1). Public API = contract
/// 00-overview 7.2.17; the `show` lists below are every exported name, and
/// everything under `src/` is private. This is the package's only entry point
/// (contract 7.1).
library;

export 'src/di/dev_overlay_section.dart'
    show DevOverlaySection, devOverlaySectionsProvider;
export 'src/di/editor_extensions.dart'
    show
        EditorExtensions,
        EditorMenuItem,
        EditorMenuContext,
        editorExtensionsProvider;
export 'src/di/stylus_extras.dart'
    show
        StylusExtrasSource,
        StylusExtraEvent,
        StylusDoubleTap,
        StylusSqueeze,
        StylusBarrelRoll,
        NoStylusExtras,
        stylusExtrasProvider;
export 'src/editor_screen.dart' show EditorScreen, featureEditorOverrides;
export 'src/state/settings/editor_settings.dart'
    show
        EditorSettings,
        InputMode,
        PageFlipMode,
        PalmRejectionSettings,
        GestureSettings;
export 'src/state/settings/editor_settings_notifier.dart'
    show EditorSettingsNotifier, editorSettingsProvider;
export 'src/ui/settings/editor_settings_sections.dart'
    show
        EditorInputSettingsSection,
        EditorPenSettingsSection,
        EditorPageSettingsSection,
        EditorDeveloperSettingsSection;
