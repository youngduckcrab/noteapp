// PageSizeMm (05-library 6.12, 8 L3): mm view of CORE's PageSizeLimits.
import 'package:feature_library/src/model/page_size_mm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

void main() {
  test('input range from PageSizeLimits, rounded inward', () {
    expect(PageSizeMm.minInputMm, 35.3);
    expect(PageSizeMm.maxInputMm, 1058.3);
  });

  test('isValidInput at the boundaries', () {
    expect(PageSizeMm.isValidInput(35.2), isFalse);
    expect(PageSizeMm.isValidInput(35.3), isTrue);
    expect(PageSizeMm.isValidInput(210), isTrue);
    expect(PageSizeMm.isValidInput(1058.3), isTrue);
    expect(PageSizeMm.isValidInput(1058.4), isFalse);
    expect(PageSizeMm.isValidInput(double.nan), isFalse);
    expect(PageSizeMm.isValidInput(double.infinity), isFalse);
    expect(PageSizeMm.isValidInput(-1), isFalse);
  });

  test('every accepted 0.1 mm input converts into PageSizeLimits', () {
    for (var tenths = 353; tenths <= 10583; tenths++) {
      final mm = tenths / 10;
      final pt = PageSizeMm.toPt(mm);
      expect(PageSizeMm.isValidInput(mm), isTrue, reason: '$mm');
      expect(pt, greaterThanOrEqualTo(PageSizeLimits.userMinSidePt));
      expect(pt, lessThanOrEqualTo(PageSizeLimits.userMaxSidePt));
    }
  });

  test('conversion round trip and A4 width', () {
    expect(PageSizeMm.toPt(210), closeTo(595.2756, 0.0001));
    expect(PageSizeMm.toMm(PageSizeMm.toPt(123.4)), closeTo(123.4, 1e-9));
    expect(PageSizeMm.toMm(72), closeTo(25.4, 1e-9));
  });

  test('clampInput', () {
    expect(PageSizeMm.clampInput(10), 35.3);
    expect(PageSizeMm.clampInput(5000), 1058.3);
    expect(PageSizeMm.clampInput(210), 210);
    expect(PageSizeMm.clampInput(double.nan), 35.3);
  });
}
