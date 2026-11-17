// The look of the rendered view (08-markdown 8.3, B-3). Colours come only from StyleTokens
// and the ColorScheme of the nearest theme — the app wraps the screen in the editor style
// (EditorStyleScope), so 크래프트 · 미니멀 · 스튜디오 and light / dark follow.
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

/// Monospace family with fallbacks (Android: 'monospace' = the system mono font).
const String kMonoFamily = 'monospace';
const List<String> kMonoFallback = [
  'RobotoMono',
  'Menlo',
  'Consolas',
  'DejaVu Sans Mono',
  'Noto Sans Mono',
  'Courier New',
  // Hangul inside code: the app's own Korean font when it is loaded (ink_engine).
  'NoteSans',
];

/// Widest reading column.
const double kReadingWidth = 720;

/// Indent of each nested list level.
const double kListIndent = 24;

@immutable
final class MdStyle {
  const MdStyle({
    required this.tokens,
    required this.scheme,
    required this.body,
    required this.headings,
    required this.inlineCode,
    required this.codeBlock,
    required this.small,
  });

  factory MdStyle.of(BuildContext context) {
    final theme = Theme.of(context);
    final t = StyleTokens.of(context);
    // A tablet is read at arm's length (stylus in hand): 17 px body there, 16 on a phone.
    final tablet = (MediaQuery.maybeSizeOf(context)?.shortestSide ?? 0) >= 600;
    final k = tablet ? 17 / 16 : 1.0;
    final base = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: 16 * k,
      height: 1.6,
      color: t.textPrimary,
      fontWeight: FontWeight.w400,
    );
    TextStyle h(double size, FontWeight w, {Color? color}) => base.copyWith(
      fontSize: (size * k).roundToDouble(),
      fontWeight: w,
      height: 1.35,
      color: color ?? t.textPrimary,
    );
    final mono = base.copyWith(
      fontFamily: kMonoFamily,
      fontFamilyFallback: kMonoFallback,
      fontSize: tablet ? 14.5 : 14,
      height: 1.5,
    );
    return MdStyle(
      tokens: t,
      scheme: theme.colorScheme,
      body: base,
      headings: [
        h(28, FontWeight.w700),
        h(23, FontWeight.w700),
        h(20, FontWeight.w600),
        h(18, FontWeight.w600),
        h(16, FontWeight.w600),
        h(15, FontWeight.w600, color: t.textSecondary),
      ],
      inlineCode: mono.copyWith(
        fontSize: tablet ? 15 : 14.5,
        color: t.onAccentSoft,
        backgroundColor: t.accentSoft,
      ),
      codeBlock: mono,
      small: base.copyWith(fontSize: 13, height: 1.45, color: t.textSecondary),
    );
  }

  final StyleTokens tokens;
  final ColorScheme scheme;

  /// Paragraphs: 16 px (17 on a tablet), line height 1.6, textPrimary.
  final TextStyle body;

  /// h1 … h6.
  final List<TextStyle> headings;
  final TextStyle inlineCode;
  final TextStyle codeBlock;
  final TextStyle small;

  /// Links: textPrimary with a 2 px accent underline (accent alone has no text contrast
  /// guarantee — review U14).
  TextStyle link(TextStyle base) => base.copyWith(
    color: tokens.textPrimary,
    decoration: TextDecoration.underline,
    decorationColor: tokens.accent,
    decorationThickness: 2,
  );

  /// Body text inside a block quote.
  TextStyle quoted(TextStyle base) =>
      base.copyWith(color: tokens.textSecondary);

  /// Side padding of the reading column: 16 on a phone, 32 on a tablet.
  static double sidePadding(double width) => width < 600 ? 16 : 32;
}
