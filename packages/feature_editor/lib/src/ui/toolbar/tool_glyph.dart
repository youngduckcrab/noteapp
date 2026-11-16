// lib/src/ui/toolbar/tool_glyph.dart — (UI stage 2, 04-editor 22) the
// toolbar's line icons and the small tool names under 올가미 · 도형 · 텍스트 ·
// 삽입.
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

/// The icon of a toolbar button: an [AppIcon] of [kind], and with [caption]
/// its small name under it — always in 크래프트 / 스튜디오, only while a
/// pointer or a hovering stylus is over the button in 미니멀
/// (StyleTokens.toolLabels) — and there only while '펜을 띄우면 이름 보기'
/// (HoverNames) is on: off means no names on hover anywhere. The hover is
/// the whole button's when a [ToolHover] wraps it (else the glyph's own).
/// The icon follows the ambient [IconTheme] (the button's active / disabled
/// colour); the name is [StyleTokens.textSecondary], the icon's colour while
/// [selected]. The box is [size] wide and high in both modes, so a name that
/// comes and goes never moves the row.
class ToolGlyph extends StatefulWidget {
  const ToolGlyph(
    this.kind, {
    super.key,
    this.caption,
    this.size = toolbarIconSize,
    this.semanticLabel,
    this.selected = false,
  });

  final AppIconKind kind;

  /// The button is the active tool: the name takes the icon's colour.
  final bool selected;
  final String? caption;

  /// The icon's semantics label (an [IconButton] has none of its own).
  final String? semanticLabel;

  /// The square the icon (and caption) take.
  final double size;

  /// The line icons of the toolbar (the mockups' 22 px).
  static const double toolbarIconSize = 22;

  /// The box of a captioned glyph (inside a 48 px button).
  static const double captionedHeight = 38;

  /// Key of the caption text (tests).
  static ValueKey<String> captionKey(String caption) =>
      ValueKey<String>('editor.toolbar.caption.$caption');

  @override
  State<ToolGlyph> createState() => _ToolGlyphState();
}

class _ToolGlyphState extends State<ToolGlyph> {
  bool _hover = false;

  void _setHover(bool value) {
    if (_hover != value) setState(() => _hover = value);
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.caption;
    if (caption == null) {
      return AppIcon(
        widget.kind,
        size: widget.size,
        semanticLabel: widget.semanticLabel,
      );
    }
    final tokens = StyleTokens.of(context);
    final always = tokens.toolLabels == ToolLabelMode.always;
    final region = ToolHover._of(context);
    final hovered =
        (region ?? _hover) &&
        tokens.toolLabels == ToolLabelMode.onHover &&
        HoverNames.enabledOf(context);
    final shown = always || hovered;
    final iconColor = IconTheme.of(context).color ?? tokens.textPrimary;
    // Dimmed with the icon (a disabled button).
    final color = widget.selected
        ? iconColor
        : tokens.textSecondary.withValues(
            alpha: tokens.textSecondary.a * iconColor.a,
          );
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 140);
    final glyph = SizedBox(
      width: 46,
      height: ToolGlyph.captionedHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedAlign(
            duration: duration,
            curve: Curves.easeOut,
            alignment: shown ? Alignment.topCenter : Alignment.center,
            child: Padding(
              padding: EdgeInsets.only(top: shown ? 1 : 0),
              child: AppIcon(
                widget.kind,
                size: shown ? 20 : widget.size,
                semanticLabel: widget.semanticLabel,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedOpacity(
              duration: duration,
              opacity: shown ? 1 : 0,
              child: Text(
                caption,
                key: ToolGlyph.captionKey(caption),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                // Grows a little with the system text size; the 38 px box
                // holds 1.15×.
                textScaler: MediaQuery.textScalerOf(context)
                    .clamp(maxScaleFactor: 1.15),
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (always || region != null) return glyph;
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: glyph,
    );
  }
}

/// The hover area of a toolbar button for the [ToolGlyph] in it: the whole
/// button (48 px), not only the glyph, shows a 미니멀 name.
class ToolHover extends StatefulWidget {
  const ToolHover({super.key, required this.child});

  final Widget child;

  static bool? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ToolHoverScope>()?.hovered;

  @override
  State<ToolHover> createState() => _ToolHoverState();
}

class _ToolHoverState extends State<ToolHover> {
  bool _hovered = false;

  void _set(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _set(true),
    onExit: (_) => _set(false),
    child: _ToolHoverScope(hovered: _hovered, child: widget.child),
  );
}

class _ToolHoverScope extends InheritedWidget {
  const _ToolHoverScope({required this.hovered, required super.child});

  final bool hovered;

  @override
  bool updateShouldNotify(_ToolHoverScope oldWidget) =>
      oldWidget.hovered != hovered;
}
