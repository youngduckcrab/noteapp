// package:note_core/testing_vm.dart — VM tests only (lib_exceptions, 7.4.2)
/// VM-only test helper of note_core (contract 00-overview 7.6, CORE 4.10). Import from
/// `test/` only; it will use `dart:ffi` / `package:drift/native.dart` from CORE T6.
library;

import 'package:clock/clock.dart';

import 'src/common/ids.dart';
import 'src/repo/note_store.dart';
import 'src/repo/status.dart';

/// Real CORE on NativeDatabase (filePath null = in-memory). deviceNodeId fixes the HLC node.
/// storageInfo: value reported by NoteStore.storageInfo; null = the real backend
/// (in-memory → nativeMemory → notDurable banner).
/// CORE: two-device tests (SYNC T16, CORE 6.10 counterexample) pass different deviceNodeIds.
/// Signature in B2, body UnimplementedError until CORE T6.
Future<NoteStore> openTestNoteStore({
  Clock? clock,
  IdGenerator? ids,
  OwnerId ownerId = kLocalOwnerId,
  String? filePath,
  String? deviceNodeId,
  bool seedDefaultPenPresets = true,
  StorageInfo? storageInfo,
}) async => throw UnimplementedError(
  'openTestNoteStore: the SQLite store arrives with CORE T6 '
  '(foundation step B2 ships the signature only)',
);
