// 2차 foundation step R2-B1 smoke test: the (still empty) entry point compiles
// and the package's tests run under `ws test`. The owning area replaces it.
import 'package:flutter_test/flutter_test.dart';
// ignore: unused_import
import 'package:ink_recognition/ink_recognition.dart';

void main() {
  test('ink_recognition entry point is importable', () {
    expect(true, isTrue);
  });
}
