// 2차 foundation step R2-B1 smoke test: the (still empty) entry point compiles
// and the package's tests run under `ws test`. The owning area replaces it.
import 'package:flutter_test/flutter_test.dart';
// ignore: unused_import
import 'package:media_io/media_io.dart';

void main() {
  test('media_io entry point is importable', () {
    expect(true, isTrue);
  });
}
