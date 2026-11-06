// Object matrices (m5-7/06-pdf 6.2.3; 8.2 T21): the frame matrix lands the local rect's four
// corners on core.ElementFrame.corners (rotation 0 · 90° · −30° · 180°, ±1e-6), the image unit
// square maps onto a y-down rect (PDF image space is y up: (0, 1) = the top-left pixel), text
// space is flipped (glyph up = screen up), and F ∘ U / F ∘ T put an image / a baseline on the
// rotated frame. The cases live in support/compose_v2_cases.dart (the browser twin is
// web/pure_logic_browser_test).
import '../support/compose_v2_cases.dart';

void main() => affineCases();
