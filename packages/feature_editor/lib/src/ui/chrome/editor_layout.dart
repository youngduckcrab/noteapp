// lib/src/ui/chrome/editor_layout.dart — (v2.16-ui, m5-7/04-editor 24) the
// editor's layout shell per editor style: 크래프트's full-width top toolbar,
// 미니멀's floating pill over the page, 스튜디오's slim top bar and left rail.
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

/// Where the editor's tools stand (04-editor 24.1).
enum EditorLayout {
  /// 크래프트 (and any theme without style tokens): the full-width toolbar
  /// over the page area (04-editor 22–23).
  topBar,

  /// 미니멀: a thin rounded pill floating over the top centre of the page
  /// area; the pages run on under it (more writing room).
  floatingBar,

  /// 스튜디오: a slim top bar (←, title, [+], undo / redo, pages, 🔍, ⋯)
  /// and a left rail (the pen tray standing vertically, the tools with
  /// their names, 6 colours and 3 widths of the current pen).
  rail,
}

/// The layout rules (04-editor 24.1).
abstract final class EditorLayouts {
  /// 스튜디오 keeps the rail from this body width; narrower (split screen,
  /// a phone) it falls back to the top toolbar, which folds and scrolls
  /// gracefully there.
  static const double railMinWidth = 600;

  /// The layout of [style] in a body of [size].
  static EditorLayout resolve(AppStyle? style, Size size) => switch (style) {
    AppStyle.calm => EditorLayout.floatingBar,
    AppStyle.studio when size.width >= railMinWidth => EditorLayout.rail,
    _ => EditorLayout.topBar,
  };

  /// The layout in [context]'s editor style (StyleTokens.style; a theme
  /// without tokens is 크래프트).
  static EditorLayout of(BuildContext context, Size size) =>
      resolve(StyleTokens.of(context).style, size);
}

/// What a widget reads from [EditorShellScope] (InheritedModel aspects: the
/// page viewport only depends on the metrics, not on the bar widget built
/// again with every EditorBody layout pass).
enum EditorShellAspect { layout, bar, metrics }

/// What EditorBody tells the page area about the shell: the layout, the
/// floating bar to show over the pages (미니멀 — EditorFloatingLayer places
/// it), the strip it covers at the top (ViewportController.topInset; the
/// banners at the top of the page area stay under it) and (스튜디오) the
/// page width the fit zoom keeps while the rail folds away in 집중 모드
/// ([fitWidth] — ViewportController.updateViewportSize's fitReserve).
class EditorShellScope extends InheritedModel<EditorShellAspect> {
  const EditorShellScope({
    super.key,
    required this.layout,
    this.floatingBar,
    this.topInset = 0,
    this.fitWidth,
    required super.child,
  });

  final EditorLayout layout;
  final Widget? floatingBar;
  final double topInset;

  /// (v2.16-ui review) The page area's width with the rail shown (스튜디오);
  /// null elsewhere. A wider page area (the rail folding away) keeps the
  /// zoom of this width: the page does not grow and jump under the pen.
  final double? fitWidth;

  static EditorShellScope? _of(BuildContext context, EditorShellAspect a) =>
      InheritedModel.inheritFrom<EditorShellScope>(context, aspect: a);

  /// The layout (null outside a shell).
  static EditorLayout? layoutOf(BuildContext context) =>
      _of(context, EditorShellAspect.layout)?.layout;

  /// The floating bar to show over the pages (미니멀), else null.
  static Widget? floatingBarOf(BuildContext context) =>
      _of(context, EditorShellAspect.bar)?.floatingBar;

  /// The covered top strip of the page area (0 outside a floating shell).
  static double topInsetOf(BuildContext context) =>
      _of(context, EditorShellAspect.metrics)?.topInset ?? 0;

  /// [fitWidth] of the enclosing shell.
  static double? fitWidthOf(BuildContext context) =>
      _of(context, EditorShellAspect.metrics)?.fitWidth;

  @override
  bool updateShouldNotify(EditorShellScope oldWidget) =>
      layout != oldWidget.layout ||
      floatingBar != oldWidget.floatingBar ||
      topInset != oldWidget.topInset ||
      fitWidth != oldWidget.fitWidth;

  @override
  bool updateShouldNotifyDependent(
    EditorShellScope oldWidget,
    Set<EditorShellAspect> dependencies,
  ) =>
      (dependencies.contains(EditorShellAspect.layout) &&
          layout != oldWidget.layout) ||
      (dependencies.contains(EditorShellAspect.bar) &&
          floatingBar != oldWidget.floatingBar) ||
      (dependencies.contains(EditorShellAspect.metrics) &&
          (topInset != oldWidget.topInset || fitWidth != oldWidget.fitWidth));
}
