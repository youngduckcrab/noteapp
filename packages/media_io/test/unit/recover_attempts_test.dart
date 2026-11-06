// Recovery attempts (m5-7/06-pdf 6.10.3; 8.2 T31a — media.recoverAttempts, device): written
// before the attempt, cleared after success / a permanent failure, entries of drafts that no
// longer exist dropped, [다시 시도] back to 0, stuck at recoverMaxAttempts (2). On CORE's fake
// store settings (createFakeNoteStore — contract 7.6).
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/providers.dart';
import 'package:media_io/src/record/recover_attempts.dart';
import 'package:media_io/src/tuning.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

void main() {
  late core.NoteStore store;
  late RecoverAttempts attempts;

  setUp(() {
    store = core_testing.createFakeNoteStore();
    attempts = RecoverAttempts(store.settings);
  });

  tearDown(() => store.close());

  test('the key: media.recoverAttempts, jsonMap, device scope', () {
    final key = MediaSettingKeys.recoverAttempts;
    expect(key.name, 'media.recoverAttempts');
    expect(key.scope, core.SettingScope.device);
    expect(key.defaultValue, isEmpty);
  });

  test('increment before the attempt, clear after it', () async {
    expect(await attempts.read(), isEmpty);
    expect(await attempts.increment('d1'), 1);
    expect(await store.settings.get(MediaSettingKeys.recoverAttempts), {
      'd1': 1,
    });
    expect(await attempts.increment('d1'), 2);
    expect(await attempts.increment('d2'), 1);
    expect(await attempts.read(), {'d1': 2, 'd2': 1});
    await attempts.clear('d1');
    expect(await attempts.read(), {'d2': 1});
    await attempts.clear('d1'); // already gone
    await attempts.clear('d2');
    expect(await attempts.read(), isEmpty);
    expect(await store.settings.get(MediaSettingKeys.recoverAttempts), isEmpty);
  });

  test('stuck at recoverMaxAttempts', () async {
    expect(MediaTuning.recoverMaxAttempts, 2);
    await attempts.increment('d');
    expect(RecoverAttempts.isStuck(await attempts.of('d')), isFalse);
    await attempts.increment('d');
    expect(RecoverAttempts.isStuck(await attempts.of('d')), isTrue);
    expect(RecoverAttempts.isStuck(await attempts.of('other')), isFalse);
  });

  test('[다시 시도] sets the count back to 0', () async {
    await attempts.increment('d');
    await attempts.increment('d');
    await attempts.reset('d');
    expect(await attempts.of('d'), 0);
    expect(RecoverAttempts.isStuck(await attempts.of('d')), isFalse);
  });

  test('prune drops drafts that no longer exist', () async {
    await attempts.increment('gone');
    await attempts.increment('kept');
    await attempts.increment('kept');
    expect(await attempts.prune(['kept', 'new']), {'kept': 2});
    expect(await attempts.read(), {'kept': 2});
    expect(await attempts.prune(const []), isEmpty);
    expect(await attempts.read(), isEmpty);
  });

  test('non-number or non-positive values read as no entry', () async {
    await store.settings.set(MediaSettingKeys.recoverAttempts, {
      'a': 'x',
      'b': 0,
      'c': 1.0,
      'd': -3,
    });
    expect(await attempts.read(), {'c': 1});
    expect(await attempts.increment('b'), 1);
  });
}
