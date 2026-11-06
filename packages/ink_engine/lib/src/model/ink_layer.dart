// lib/src/model/ink_layer.dart — 03-ink 4.1 (contract 7.2.9 v2.0: + cover).

/// Render layer of a stroke (PLAN 7.3, L-1): highlighter → ink → cover (memorization
/// tape, above the annotation objects).
enum InkLayer { highlighter, ink, cover }
