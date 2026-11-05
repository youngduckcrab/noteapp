// app/tool/prepare_web_test.dart (docs/plans/01-infra.md 3.4, 4.2): copies
// the two committed web assets next to the Chrome tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/prepare_web_test.dart';

void main() {
  test('copies web/sqlite3.wasm and web/drift_worker.js to test/web/', () {
    final app = Directory.systemTemp.createTempSync('prepare_web_test_');
    addTearDown(() => app.deleteSync(recursive: true));
    Directory('${app.path}/web').createSync();
    File('${app.path}/web/sqlite3.wasm').writeAsBytesSync([0, 97, 115, 109]);
    File('${app.path}/web/drift_worker.js').writeAsStringSync('// worker');

    final copied = prepareWebTest(app.path);
    expect(copied, [
      '${app.path}/test/web/sqlite3.wasm',
      '${app.path}/test/web/drift_worker.js',
    ]);
    expect(File('${app.path}/test/web/sqlite3.wasm').readAsBytesSync(), [
      0,
      97,
      115,
      109,
    ]);
    expect(
      File('${app.path}/test/web/drift_worker.js').readAsStringSync(),
      '// worker',
    );
    // Running again overwrites.
    expect(prepareWebTest(app.path), hasLength(2));
  });

  test('a missing source throws', () {
    final app = Directory.systemTemp.createTempSync('prepare_web_test_');
    addTearDown(() => app.deleteSync(recursive: true));
    expect(() => prepareWebTest(app.path), throwsA(isA<FileSystemException>()));
  });

  test('the committed web assets are the ones copied', () {
    expect(webTestAssets, ['sqlite3.wasm', 'drift_worker.js']);
    for (final name in webTestAssets) {
      expect(File('web/$name').existsSync(), isTrue, reason: name);
    }
  });
}
