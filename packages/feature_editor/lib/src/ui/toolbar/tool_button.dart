// lib/src/ui/toolbar/tool_button.dart — 04-editor 6.9.1 (tool buttons).
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import 'tool_glyph.dart';

/// A toolbar tool button: 48×48 touch area (≥ 44 — contract 7.4.8), active =
/// the style's `accentSoft` well, optional 8 px colour dot under the icon
/// (pen). Tap and long press; no long-press tooltip (long press is taken) —
/// a semantics label, and (UI stage 2) the [label] as a [HoverName] while a
/// stylus hovers over an icon-only button.
///
/// (UI stage 2) [glyph] draws the ui_kit line icon instead of [icon]; with
/// [caption] the small name shows under it ([ToolGlyph], StyleTokens
/// .toolLabels).
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    this.icon,
    this.glyph,
    this.caption,
    required this.label,
    required this.active,
    this.onTap,
    this.onLongPress,
    this.dotColor,
  }) : assert(icon != null || glyph != null, 'an icon or a glyph');

  final IconData? icon;

  /// (UI stage 2) The line icon (wins over [icon]).
  final AppIconKind? glyph;

  /// (UI stage 2) The small name under [glyph].
  final String? caption;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    final enabled = onTap != null;
    final foreground = !enabled
        ? tokens.textPrimary.withValues(alpha: 0.38)
        : active
        ? tokens.onAccentSoft
        : tokens.textPrimary;
    final dot = dotColor;
    final kind = glyph;
    final iconWidget = kind != null
        ? IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: ToolGlyph(kind, caption: caption),
          )
        : Icon(icon, size: 22, color: foreground);
    final button = Semantics(
      container: true,
      button: true,
      selected: active,
      enabled: enabled,
      label: label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: active ? tokens.accentSoft : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSmall + 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: enabled ? onLongPress : null,
            excludeFromSemantics: false,
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconWidget,
                  if (dot != null) ...[
                    const SizedBox(height: 2),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        // (v2.14-ui) a stronger ring when the ink would
                        // vanish on the toolbar.
                        border: Border.all(
                          color: tokens.swatchRing(dot, tokens.toolbar),
                          width: 0.5,
                        ),
                      ),
                      child: const SizedBox(width: 8, height: 8),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (caption != null && kind != null) return button;
    return HoverName(name: label, child: button);
  }
}
