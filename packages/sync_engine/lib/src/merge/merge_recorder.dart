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
  /// Starts a fresh scratch map for one applyRemote call. StateError if a call is open.
  void beginCall() => throw UnimplementedError('SYNC T4');

  /// The policy records into the open call's scratch map (overwritten by ref, so a CORE
  /// retry of the same transaction inside one call yields the same map). Pure apart from
  /// that write; StateError if no call is open.
  RemoteMergePolicy wrap(RemoteMergePolicy policy) =>
      throw UnimplementedError('SYNC T4');

  /// applyRemote returned normally: merges the scratch map into [outcomes] and closes the
  /// call. Per ref, `created` wins over a later outcome (a ref appears in at most one call
  /// of a group because step 4 merges records per ref, so this is only a guard); otherwise
  /// the later call wins.
  void commitCall() => throw UnimplementedError('SYNC T4');

  /// applyRemote threw (transaction rolled back): drops the scratch map, closes the call.
  void discardCall() => throw UnimplementedError('SYNC T4');

  /// Committed outcomes of the current apply group.
  Map<EntityRef, MergeOutcomeKind> get outcomes =>
      throw UnimplementedError('SYNC T4');

  /// Forgets everything (start of the next apply group). StateError if a call is open.
  void clear() => throw UnimplementedError('SYNC T4');
}
