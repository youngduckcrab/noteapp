// lib/src/ui/presets/preset_chip.dart — 04-editor 6.10 (preset chip).
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../toolbar/editor_toolbar.dart' show penTypeIcon;

/// One preset of the bar: 56×40 (touch area 56×44). A 22 px circle in the
/// preset's colour and opacity with a width dot inside (diameter
/// [dotDiameter]), the pen type's small icon at the bottom right and the name
/// under it (10 px, ellipsis). [active] (the preset's style equals the active
/// pen's — core.StrokeStyle value equality) draws a 2 px primary border.
class PresetChip extends StatelessWidget {
  const PresetChip({
    super.key,
    required this.preset,
    required this.active,
    this.onTap,
  });

  final core.PenPreset preset;
  final bool active;
  final VoidCallback? onTap;

  static const double width = 56;
  static const double height = 40;
  static const double touchHeight = 44;
  static const double circleDiameter = 22;

  /// Key of the coloured circle (its decoration carries the preset colour).
  static const circleKey = ValueKey('editor.presetChip.circle');

  /// Key of the width dot inside the circle.
  static const dotKey = ValueKey('editor.presetChip.dot');

  /// Width dot: 4 + 16·sqrt(width / 30) (width 0.1–30 pt → 4.9–20 px).
  static double dotDiameter(double width) =>
      4 + 16 * math.sqrt(width.clamp(0, core.StrokeStyle.maxWidth) / 30);

  /// The one of `surface` / `onSurface` that stands out more on [color]
  /// (colours come from the colour scheme only — contract 7.4.11).
  static Color dotColorOn(Color color, ColorScheme scheme) {
    final l = color.computeLuminance();
    final a = scheme.surface.computeLuminance();
    final b = scheme.onSurface.computeLuminance();
    return (l - a).abs() >= (l - b).abs() ? scheme.surface : scheme.onSurface;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = preset.style;
    final color = Color(style.colorArgb).withValues(alpha: style.opacity);
    // The dot is judged against the colour as it shows on the bar.
    final shown = Color.alphaBlend(color, scheme.surface);
    final dot = dotDiameter(style.width);
    return Semantics(
      container: true,
      button: true,
      selected: active,
      enabled: onTap != null,
      label: preset.name,
      child: SizedBox(
        width: width,
        height: touchHeight,
        child: Center(
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: active
                  ? BorderSide(color: scheme.primary, width: 2)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ExcludeSemantics(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: circleDiameter + 8,
                        height: circleDiameter,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            DecoratedBox(
                              key: circleKey,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                  width: 0.5,
                                ),
                              ),
                              child: const SizedBox.square(
                                dimension: circleDiameter,
                              ),
                            ),
                            DecoratedBox(
                              key: dotKey,
                              decoration: BoxDecoration(
                                color: dotColorOn(shown, scheme),
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox.square(dimension: dot),
                            ),
                            Positioned(
                              right: -2,
                              bottom: -3,
                              child: Icon(
                                penTypeIcon(style.tool),
                                size: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          preset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            height: 1.2,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
