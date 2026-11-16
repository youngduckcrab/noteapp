/// The pen tray's look per screen style (contract 7.1 v2.15-ui, 04-editor
/// 22): where the pens stand in the editor toolbar.
library;

import 'package:material_ui/material_ui.dart';

import 'app_style.dart';
import 'style_tokens.dart';

/// How the tray shows its pens.
enum PenTrayLook {
  /// Pen drawings standing in a recessed well (크래프트, 스튜디오).
  drawings,

  /// Flat ink-stroke chips, no drawings (미니멀).
  strokes,
}

/// The tray colours of one style in one brightness. Read with
/// [PenTrayStyle.of]; derived from the [StyleTokens] (style + brightness),
/// so no new token is needed.
@immutable
final class PenTrayStyle {
  const PenTrayStyle({
    required this.look,
    required this.wellTop,
    required this.wellBottom,
    required this.wellBorder,
    required this.divider,
    required this.innerShadow,
    required this.liftShadow,
    required this.chipFill,
    required this.chipActiveFill,
    required this.chipActiveBorder,
    required this.activeMark,
  });

  /// [look] of the tray.
  final PenTrayLook look;

  /// The well's gradient (top → bottom); transparent for a flat tray.
  final Color wellTop;
  final Color wellBottom;

  /// The well's rim.
  final Color wellBorder;

  /// The line between the pens and the eraser.
  final Color divider;

  /// The dark edge along the well's top (the recess).
  final Color innerShadow;

  /// Shadow under the lifted pen.
  final Color liftShadow;

  /// Background of a stroke chip (transparent = the toolbar shows through).
  final Color chipFill;

  /// Background and border of the active stroke chip.
  final Color chipActiveFill;
  final Color chipActiveBorder;

  /// The small bar under the active chip / the hover ring.
  final Color activeMark;

  static const _transparent = Color(0x00000000);

  /// The tray style of [tokens].
  factory PenTrayStyle.of(StyleTokens tokens) {
    final dark = tokens.isDark;
    switch (tokens.style) {
      case AppStyle.calm:
        return PenTrayStyle(
          look: PenTrayLook.strokes,
          wellTop: _transparent,
          wellBottom: _transparent,
          wellBorder: _transparent,
          divider: tokens.hairline,
          innerShadow: _transparent,
          liftShadow: tokens.shadow.withValues(alpha: dark ? .5 : .12),
          // Ink is document data: a dark style shows it on paper-light chips.
          chipFill: dark
              ? tokens.inkSwatch.withValues(alpha: .92)
              : _transparent,
          chipActiveFill: tokens.inkSwatch,
          chipActiveBorder: dark ? tokens.accent : tokens.hairline,
          activeMark: tokens.accent,
        );
      case AppStyle.studio:
        // A cool dark strip like the studio rail, in both brightnesses.
        return PenTrayStyle(
          look: PenTrayLook.drawings,
          wellTop: dark ? const Color(0xFF14161A) : const Color(0xFF2A2E35),
          wellBottom: dark ? const Color(0xFF1C1F24) : const Color(0xFF353A42),
          wellBorder: dark ? const Color(0xFF0E1013) : const Color(0xFF22252B),
          divider: dark ? const Color(0xFF3A3F47) : const Color(0xFF4A505A),
          innerShadow: const Color(0x66000000),
          liftShadow: const Color(0x99000000),
          chipFill: _transparent,
          chipActiveFill: tokens.inkSwatch,
          chipActiveBorder: tokens.accent,
          activeMark: tokens.accent,
        );
      case AppStyle.craft:
        return PenTrayStyle(
          look: PenTrayLook.drawings,
          // Warm recessed wood / paper well (the craft mockup).
          wellTop: dark ? const Color(0xFF332D26) : const Color(0xFFD9D0C1),
          wellBottom: dark ? const Color(0xFF453D33) : const Color(0xFFE9E2D6),
          wellBorder: dark ? const Color(0xFF443E36) : const Color(0xFFD3C9B9),
          divider: dark ? const Color(0xFF4D463D) : const Color(0xFFCFC4B2),
          innerShadow: dark ? const Color(0x80000000) : const Color(0x26584A33),
          liftShadow: dark ? const Color(0xB3000000) : const Color(0x47000000),
          chipFill: _transparent,
          chipActiveFill: tokens.inkSwatch,
          chipActiveBorder: tokens.accent,
          activeMark: tokens.accent,
        );
    }
  }

  /// Whether the well is drawn (a [PenTrayLook.strokes] tray is flat).
  bool get hasWell => look == PenTrayLook.drawings;
}
