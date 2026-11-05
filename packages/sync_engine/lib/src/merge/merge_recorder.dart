// Internal (not exported).
import 'package:note_core/note_core.dart';

/// created = TakeRemote with local == null (new to this device), taken = other TakeRemote,
/// merged = WriteMerged, kept = KeepLocal (incl. an unsent local purge, 6.3.4).
enum MergeOutcomeKind { created, taken, merged, kept }

/// Records, per ref, what the policy decided in the applyRemote calls of ONE apply group
/// (6.6.3 step 6) — input of the folder-cycle and page-resurrection checks (6.7).
/// Only calls whose applyRemote returned normally count: a rolled-back call (CORE threw,
/// so nothing was written) must not leave outcomes behind.
///
///   recorder.clear();                          // start of an apply group
///   for each piece (the group, or its bisected halves):
///     recorder.beginCall();
///     try { await sync.applyRemote(piece, policy: recorder.wrap(SyncMergePolicy.decide), …);
///           recorder.commitCall(); }
///     catch (_) { recorder.discardCall(); … bisect / skip … }
///   checks(recorder.outcomes);                 // once, after every piece of the group
final class MergeRecorder {
  Map<EntityRef, MergeOutcomeKind>? _scratch;
  final Map<EntityRef, MergeOutcomeKind> _outcomes = {};

  /// A call is open (between beginCall and commitCall / discardCall).
  bool get isCallOpen => _scratch != null;

  /// Starts a fresh scratch map for one applyRemote call. StateError if a call is open.
  void beginCall() {
    if (_scratch != null) {
      throw StateError('MergeRecorder: a call is already open');
    }
    _scratch = {};
  }

  /// The policy records into the open call's scratch map (overwritten by ref, so a CORE
  /// retry of the same transaction inside one call yields the same map). Pure apart from
  /// that write; StateError if no call is open.
  RemoteMergePolicy wrap(RemoteMergePolicy policy) => (local, remote, pending) {
    final scratch = _scratch;
    if (scratch == null) {
      throw StateError('MergeRecorder: policy called with no open call');
    }
    final decision = policy(local, remote, pending);
    scratch[EntityRef(
      remote.entity.kind,
      remote.entity.id,
    )] = switch (decision) {
      TakeRemote() =>
        local == null ? MergeOutcomeKind.created : MergeOutcomeKind.taken,
      WriteMerged() => MergeOutcomeKind.merged,
      KeepLocal() => MergeOutcomeKind.kept,
    };
    return decision;
  };

  /// applyRemote returned normally: merges the scratch map into [outcomes] and closes the
  /// call. Per ref, `created` wins over a later outcome (a ref appears in at most one call
  /// of a group because step 4 merges records per ref, so this is only a guard); otherwise
  /// the later call wins.
  void commitCall() {
    final scratch = _scratch;
    if (scratch == null) throw StateError('MergeRecorder: no open call');
    for (final MapEntry(:key, :value) in scratch.entries) {
      if (_outcomes[key] == MergeOutcomeKind.created) continue;
      _outcomes[key] = value;
    }
    _scratch = null;
  }

  /// applyRemote threw (transaction rolled back): drops the scratch map, closes the call.
  void discardCall() {
    if (_scratch == null) throw StateError('MergeRecorder: no open call');
    _scratch = null;
  }

  /// Committed outcomes of the current apply group.
  Map<EntityRef, MergeOutcomeKind> get outcomes => Map.unmodifiable(_outcomes);

  /// Forgets everything (start of the next apply group). StateError if a call is open.
  void clear() {
    if (_scratch != null) {
      throw StateError('MergeRecorder: clear while a call is open');
    }
    _outcomes.clear();
  }
}
