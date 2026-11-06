// LaTeX text from engines (docs/plans/m5-7/07-sync.md 3.2, 6.9.3): cleaning an engine answer
// before it is returned, and the normalisation the comparison tool scores with (shared, so the
// server and the tool read an answer the same way). Pure functions, no dependencies.

/** Outer math delimiters an engine may wrap its answer in, longest first. */
const DELIMITERS: readonly (readonly [string, string])[] = [
  ["$$", "$$"],
  ["\\[", "\\]"],
  ["\\(", "\\)"],
  ["$", "$"],
];

/** Trims [latex] and removes one pair of outer delimiters ($$…$$, \[…\], \(…\), $…$). */
export function stripMathDelimiters(latex: string): string {
  const s = latex.trim();
  for (const [open, close] of DELIMITERS) {
    if (s.length >= open.length + close.length && s.startsWith(open) && s.endsWith(close)) {
      return s.slice(open.length, s.length - close.length).trim();
    }
  }
  return s;
}

/**
 * The 6.9.3 'normalised match' form: outer delimiters off, \left / \right removed, \dfrac and
 * \tfrac → \frac, \operatorname{name} → \name, spacing commands (\, \; \! \: '\ ' \quad \qquad)
 * removed, all whitespace removed, one-character braces after ^ and _ dropped (^{2} → ^2).
 */
export function normalizeLatex(latex: string): string {
  let s = stripMathDelimiters(latex);
  s = s.replace(/\\(?:left|right)(?![A-Za-z])/g, "");
  s = s.replace(/\\[dt]frac(?![A-Za-z])/g, "\\frac");
  s = s.replace(/\\operatorname\s*\{\s*([A-Za-z]+)\s*\}/g, "\\$1");
  s = s.replace(/\\q?quad(?![A-Za-z])/g, "");
  s = s.replace(/\\[,;!:]/g, "");
  s = s.replace(/\\ /g, "");
  s = s.replace(/\s+/g, "");
  s = s.replace(/([\^_])\{([^{}\\])\}/g, "$1$2");
  return s;
}
