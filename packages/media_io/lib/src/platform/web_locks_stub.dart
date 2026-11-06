// lib/src/platform/web_locks_stub.dart — no Web Locks (m5-7/06-pdf 6.10.2): native (one app
// instance — the active session is already left out) and the VM. pendingDrafts() keeps the
// 'recently updated' time rule only. Also web_locks_factory.dart off the web.
import 'web_locks.dart';

WebLocks createPlatformWebLocks() => const UnavailableWebLocks();

final class UnavailableWebLocks implements WebLocks {
  const UnavailableWebLocks();

  @override
  bool get available => false;

  @override
  Future<WebLockHold?> acquire(String name) async => null;

  @override
  Future<Set<String>?> heldNames() async => null;
}
