// lib/src/platform/page_events_stub.dart — page_events_factory.dart off the web (m5-7/06-pdf 6.18):
// always visible, no pagehide, no wake lock. Internal.
import 'page_events.dart';

PageEvents createPlatformPageEvents() => const AlwaysVisiblePageEvents();

final class AlwaysVisiblePageEvents implements PageEvents {
  const AlwaysVisiblePageEvents();

  @override
  bool get hidden => false;

  @override
  Stream<bool> get visibilityChanges => const Stream.empty();

  @override
  Stream<void> get pageHides => const Stream.empty();

  @override
  bool get wakeLockAvailable => false;

  @override
  Future<ScreenWakeLock?> requestWakeLock() async => null;
}
