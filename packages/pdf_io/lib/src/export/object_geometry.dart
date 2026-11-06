// lib/src/export/object_geometry.dart — m5-7/06-pdf 6.2.3. Internal (not in the barrel).
//
// Matrices from an object's own space to note pt (y down). The frame matrix itself is
// PdfAffine.frame (vectors.dart); the resolver composes F ∘ U / F ∘ T and the backends apply
// note → PDF user space last (1차 6.11.3). Web-safe.
import 'dart:ui' as ui;

import 'vectors.dart';

/// U (PDF T21): the image unit square (PDF image space — x right, y UP, (0, 1) = the top-left
/// pixel) → the rect [r] in a y-down space: [r.width, 0, 0, −r.height, r.left, r.top + r.height].
PdfAffine unitSquareToRect(ui.Rect r) =>
    PdfAffine(r.width, 0, 0, -r.height, r.left, r.top + r.height);

/// T (PDF T21): text space (origin = baseline start, x right, y UP, 1 unit = 1 pt) → the
/// baseline point ([baselineX], [baselineY]) in a y-down space: [1, 0, 0, −1, bx, by].
PdfAffine textSpaceAt(double baselineX, double baselineY) =>
    PdfAffine(1, 0, 0, -1, baselineX, baselineY);
