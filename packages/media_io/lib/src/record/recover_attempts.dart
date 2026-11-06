// lib/src/record/recover_attempts.dart — m5-7/06-pdf 6.10.3 (v2.1, PDF-M7 ④; contract 7.2.12,
// 7.4.4 media.recoverAttempts). Internal.
//
// recoverDraft writes the attempt count BEFORE it tries (an attempt that kills the tab still
// counts), clears it after success or a permanent-failure cleanup, and pendingDrafts drops the
// entries of drafts that no longer exist and leaves out drafts at recoverMaxAttempts — the big
// recovery that kills the tab is not retried on every start. The panel's [다시 시도] sets the
// count back to 0. Values are JSON numbers ({draftId: n}); anything else reads as 0.
import 'package:note_core/note_core.dart' as core;

import '../providers.dart';
import '../tuning.dart';

final class RecoverAttempts {
  RecoverAttempts(this._settings);

  final core.SettingsRepository _settings;

  /// {draftId: attempts}, only positive counts.
  Future<Map<String, int>> read() async {
    final raw = await _settings.get(MediaSettingKeys.recoverAttempts);
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        if (value is num && value.toInt() > 0) key: value.toInt(),
    };
  }

  /// Attempts of [draftId] (0 when none).
  Future<int> of(String draftId) async => (await read())[draftId] ?? 0;

  /// n + 1 for [draftId], written before the attempt; returns the new count.
  Future<int> increment(String draftId) async {
    final all = await read();
    final n = (all[draftId] ?? 0) + 1;
    await _write({...all, draftId: n});
    return n;
  }

  /// Success or a permanent failure cleaned up: the entry goes.
  Future<void> clear(String draftId) async {
    final all = await read();
    if (!all.containsKey(draftId)) return;
    await _write({...all}..remove(draftId));
  }

  /// [다시 시도] (6.10.3): back to 0 so pendingDrafts offers the draft again.
  Future<void> reset(String draftId) => clear(draftId);

  /// pendingDrafts: drops the entries of drafts not in [existing]; returns what is left.
  Future<Map<String, int>> prune(Iterable<String> existing) async {
    final all = await read();
    final keep = existing.toSet();
    final left = {
      for (final MapEntry(:key, :value) in all.entries)
        if (keep.contains(key)) key: value,
    };
    if (left.length != all.length) await _write(left);
    return left;
  }

  /// Out of automatic recovery (6.10.3 — '복구하지 못한 녹음').
  static bool isStuck(int attempts) =>
      attempts >= MediaTuning.recoverMaxAttempts;

  Future<void> _write(Map<String, int> all) => all.isEmpty
      ? _settings.reset(MediaSettingKeys.recoverAttempts)
      : _settings.set(MediaSettingKeys.recoverAttempts, <String, Object?>{
          ...all,
        });
}
