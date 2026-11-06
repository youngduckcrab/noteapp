// The backup golden file (CORE 6.17, T19): the real and the fake store export the same
// bytes for the golden state of test/shared/backup_cases.dart. VM only (the web prints
// 1.0 as 1, 7.4.6). Regenerate with UPDATE_BACKUP_GOLDEN=1 (separate commit, 7.4.8). (v2.0)
// backup_v2.json replaces backup_v1.json (m5-7/02-core 6.14.4: the new kinds in the state).
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

const String kBackupGoldenPath = 'test/goldens/backup/backup_v2.json';

void expectBackupGolden(Uint8List bytes) {
  final file = File(kBackupGoldenPath);
  if (Platform.environment['UPDATE_BACKUP_GOLDEN'] == '1') {
    file.writeAsBytesSync(bytes);
  }
  expect(bytes, file.readAsBytesSync());
}
