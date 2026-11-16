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
    this.rimLight,
    this.chipPlate = _transparent,
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

  /// (v2.15-ui review) A thin light edge on the pen drawings (PenArtPainter
  /// rimLight) where the well is dark enough to swallow a black pen; null
  /// on a light well.
  final Color? rimLight;

  /// (v2.15-ui review) The paper-light plate a flat chip gets behind an ink
  /// that would vanish on the bar ([needsPlate]); transparent = never.
  final Color chipPlate;

  /// Whether a flat chip of [ink] needs [chipPlate] behind it: a dark ink
  /// (relative luminance below .15) on a dark bar.
  bool needsPlate(Color ink) => chipPlate.a > 0 && ink.computeLuminance() < .15;

  /// Whether an ink this light needs a hairline edge on a light bar (a pale
  /// highlighter on white).
  bool needsEdge(Color ink) => chipPlate.a == 0 && ink.computeLuminance() > .6;

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
          // No plates (the calm mockup): only the active chip gets a soft
          // box and the underline. Ink is document data: in a dark style a
          // dark ink stands on a small paper-light plate ([needsPlate]).
          chipFill: _transparent,
          chipActiveFill: dark
              ? const Color(0x1FFFFFFF)
              : tokens.accentSoft.withValues(alpha: .55),
          chipActiveBorder: _transparent,
          activeMark: tokens.accent,
          chipPlate: dark
              ? tokens.inkSwatch.withValues(alpha: .86)
              : _transparent,
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
          rimLight: const Color(0x2EFFFFFF),
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
          rimLight: dark ? const Color(0x24FFFFFF) : null,
        );
    }
  }

  /// The rim light for pen drawings on a card or panel of [tokens] (the
  /// picker's pen cards): a dark style's cards are dark too.
  static Color? cardRimLightOf(StyleTokens tokens) =>
      tokens.isDark ? const Color(0x2EFFFFFF) : null;

  /// Whether the well is drawn (a [PenTrayLook.strokes] tray is flat).
  bool get hasWell => look == PenTrayLook.drawings;
}
