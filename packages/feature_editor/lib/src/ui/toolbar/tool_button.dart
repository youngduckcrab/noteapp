// lib/src/ui/toolbar/tool_button.dart — 04-editor 6.9.1 (tool buttons).
import 'package:material_ui/material_ui.dart';

/// A toolbar tool button: 48×48 touch area (≥ 44 — contract 7.4.8), active =
/// `primaryContainer` background, optional 8 px colour dot under the icon
/// (pen). Tap and long press; no tooltip (long press is taken) — a semantics
/// label only.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
    this.onLongPress,
    this.dotColor,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final foreground = !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : active
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final dot = dotColor;
    return Semantics(
      container: true,
      button: true,
      selected: active,
      enabled: enabled,
      label: label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: active ? scheme.primaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
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
                  Icon(icon, size: 22, color: foreground),
                  if (dot != null) ...[
                    const SizedBox(height: 2),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.outlineVariant,
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
  }
}
