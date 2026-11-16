// lib/src/ui/toolbar/tool_glyph.dart — (UI stage 2, 04-editor 20.2) the
// toolbar's line icons and the small tool names under 올가미 · 도형 · 텍스트 ·
// 삽입.
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

/// The icon of a toolbar button: an [AppIcon] of [kind], and with [caption]
/// its small name under it — always in 크래프트 / 스튜디오, only while a
/// pointer or a hovering stylus is over the button in 미니멀
/// (StyleTokens.toolLabels). Colours follow the ambient [IconTheme] (the
/// button's active / disabled colour). The box is [size] wide and high in
/// both modes, so a name that comes and goes never moves the row.
class ToolGlyph extends StatefulWidget {
  const ToolGlyph(
    this.kind, {
    super.key,
    this.caption,
    this.size = toolbarIconSize,
    this.semanticLabel,
  });

  final AppIconKind kind;
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
    final shown = always || _hover;
    final color = IconTheme.of(context).color;
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
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (always) return glyph;
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: glyph,
    );
  }
}
