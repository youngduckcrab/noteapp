/// Note editor screen: writing surface, input routing, toolbar, pen settings,
/// page panel and developer overlay.
///
/// Owned by EDITOR (docs/plans/04-editor.md 4.1, docs/plans/m5-7/04-editor.md
/// 4.1). Public API = contract 00-overview 7.2.17 and 2nd-round contract
/// m5-7/00-overview 7.2.10; the `show` lists below are every exported name,
/// and everything under `src/` is private. This is the package's only entry
/// point (contract 7.1).
library;

export 'src/di/dev_overlay_section.dart'
    show DevOverlaySection, devOverlaySectionsProvider;
export 'src/di/editor_extensions.dart'
    show
        EditorExtensions,
        EditorMenuItem,
        EditorMenuContext,
        editorExtensionsProvider,
        EditorSelectionContext, // (v2.0)
        EditorSelectionMenuItem,
        EditorInsertContext,
        EditorInsertMenuItem,
        EditorPanelBuilder,
        EditorPanelContext,
        EditorMathPen, // (math pen, phase 1)
        EditorMathPenContext,
        EditorMathGroup,
        EditorMathConvertTrigger,
        EditorMathPenSession;
export 'src/di/editor_image_importer.dart'
    show EditorImageImporter, editorImageImporterProvider; // (v2.0)
export 'src/di/stylus_extras.dart'
    show
        StylusExtrasSource,
        StylusExtraEvent,
        StylusDoubleTap,
        StylusSqueeze,
        StylusBarrelRoll,
        NoStylusExtras,
        stylusExtrasProvider,
        StylusHoverPose, // (v2.0)
        StylusPreferredAction,
        StylusSqueezePhase,
        StylusCapabilities;
export 'src/editor_screen.dart'
    show EditorScreen, featureEditorOverrides; // + initialFocusRectPt (v2.0)
export 'src/state/settings/editor_settings.dart'
    show
        EditorSettings,
        InputMode,
        PageFlipMode,
        PalmRejectionSettings,
        GestureSettings,
        EditorGesture, // (v2.0)
        EditorAction;
export 'src/state/settings/editor_settings_notifier.dart'
    show EditorSettingsNotifier, editorSettingsProvider;
export 'src/ui/settings/editor_settings_sections.dart'
    show
        EditorInputSettingsSection,
        EditorPenSettingsSection,
        EditorPageSettingsSection,
        EditorDeveloperSettingsSection;
