// Foundation step B1 smoke test: the (still empty) barrel compiles and the
// package's tests run under `ws test`. The owning area replaces it.
import 'package:flutter_test/flutter_test.dart';
// ignore: unused_import
import 'package:sync_engine/sync_engine.dart';

void main() {
  test('sync_engine barrel is importable', () {
    expect(true, isTrue);
  });
}
