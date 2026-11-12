// The stores and small helpers of the `media` tests (m5-7/06-pdf 8.2 T39, 9.4 — PDF-M12).
//
// V8 and V16 run on CORE's REAL web store (note_core/testing_web.dart openWebTestNoteStore —
// IndexedDB + the drift web worker; a unique name per test, deleted at the start and at the end)
// — the variant they are judged on ([MediaStores.judged], integration step 4-c). mediaStoreTest
// also runs the same body on CORE's fake store (the flow over the real Chrome MediaRecorder with
// the fake microphone, no IndexedDB), whose wall-clock-sensitive values are printed only.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:note_core/testing_web.dart' as core_web;
import 'package:web/web.dart' as web;

/// Opens, re-opens and closes the store of one media test.
abstract interface class MediaStores {
  /// 'real web store' / 'CORE fake store'.
  String get label;

  /// Whether V8 / V16 are judged on this variant (the real web store — integration step 4-c).
  /// The wall-clock-sensitive comparisons (the file timeline against the recording clock) are
  /// asserted only there; the fake store variant prints them (PDF-F1) — on a loaded machine the
  /// MediaRecorder's start / stop events come late and the two drift apart by 100 ms or more.
  bool get judged;

  /// A new, empty store.
  Future<core.NoteStore> open();

  /// The same data in a new store object (V16 'a new container'): the real web store closes
  /// [store] and opens the same name again; the fake store hands [store] back.
  Future<core.NoteStore> reopen(core.NoteStore store);

  /// Closes [store] and removes its data.
  Future<void> close(core.NoteStore store);
}

/// CORE's real web store under `<prefix>_<time>` (deleted before the first open and on close).
final class RealWebStores implements MediaStores {
  RealWebStores(String prefix)
    : name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}';

  final String name;

  @override
  String get label => 'real web store';

  @override
  bool get judged => true;

  @override
  Future<core.NoteStore> open() async {
    await core_web.deleteWebTestNoteStore(name);
    return core_web.openWebTestNoteStore(name);
  }

  @override
  Future<core.NoteStore> reopen(core.NoteStore store) async {
    await store.close();
    return core_web.openWebTestNoteStore(name);
  }

  @override
  Future<void> close(core.NoteStore store) async {
    await store.close();
    await core_web.deleteWebTestNoteStore(name);
  }
}

/// CORE's fake store (in memory; reopen = the same object).
final class FakeStores implements MediaStores {
  @override
  String get label => 'CORE fake store';

  @override
  bool get judged => false;

  @override
  Future<core.NoteStore> open() async => core_testing.createFakeNoteStore();

  @override
  Future<core.NoteStore> reopen(core.NoteStore store) async => store;

  @override
  Future<void> close(core.NoteStore store) => store.close();
}

/// Declares [body] on the real web store (judged) and on CORE's fake store.
void mediaStoreTest(
  String description,
  Future<void> Function(MediaStores stores) body, {
  required String prefix,
}) {
  const timeout = Timeout(Duration(minutes: 2));
  test(
    '$description — real web store',
    () => body(RealWebStores(prefix)),
    timeout: timeout,
  );
  test(
    '$description — CORE fake store',
    () => body(FakeStores()),
    timeout: timeout,
  );
}

/// Waits (real time — the recording itself) until [ready]; fails with [what] after ~10 s.
Future<void> until(bool Function() ready, String what) async {
  for (var i = 0; i < 1000 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: what);
}

/// [until] for an async condition.
Future<void> untilAsync(Future<bool> Function() ready, String what) async {
  for (var i = 0; i < 1000; i++) {
    if (await ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(await ready(), isTrue, reason: what);
}

/// The names navigator.locks holds now.
Future<Set<String>> heldLockNames() async {
  final snapshot = await web.window.navigator.locks.query().toDart;
  return {for (final info in snapshot.held.toDart) info.name};
}

/// Takes [name] away from whoever holds it and lets it go at once — what the browser does with
/// the locks of a tab that closes.
Future<void> stealLock(String name) async {
  JSAny? granted(web.Lock? lock) => null;
  await web.window.navigator.locks
      .request(name, web.LockOptions(steal: true), granted.toJS)
      .toDart;
}

/// Info > Duration of a WebM file (EBML ID 0x4489, an 8-byte float in TimecodeScale units —
/// 1 ms in Chrome's files) before the first Cluster, rounded; null when there is none.
int? webmInfoDurationMs(Uint8List bytes) {
  for (var i = 0; i + 11 <= bytes.length; i++) {
    if (bytes[i] == 0x1F &&
        bytes[i + 1] == 0x43 &&
        bytes[i + 2] == 0xB6 &&
        bytes[i + 3] == 0x75) {
      return null; // the first Cluster: no Duration in the head
    }
    if (bytes[i] == 0x44 && bytes[i + 1] == 0x89 && bytes[i + 2] == 0x88) {
      final value = ByteData.sublistView(bytes, i + 3, i + 11).getFloat64(0);
      return value.round();
    }
  }
  return null;
}
