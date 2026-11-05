// Shared body: HistoryLimits.platformDefault (contract 7.2.7, 7.4.10): 64 MiB on the VM,
// 32 MiB on the web (bool.fromEnvironment('dart.library.js_interop')).
import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void defineHistoryLimitsTests({required bool web}) {
  test('platformDefault: ${web ? 32 : 64} MiB, 100 steps', () {
    expect(HistoryLimits.platformDefault.maxSteps, 100);
    expect(
      HistoryLimits.platformDefault.maxBytes,
      (web ? 32 : 64) * 1024 * 1024,
    );
    expect(const NoteSessionOptions().history, HistoryLimits.platformDefault);
    expect(const NoteSessionOptions().maxCachedPages, 8);
    expect(const HistoryLimits().maxBytes, 64 * 1024 * 1024);
  });
}
