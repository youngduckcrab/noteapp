// test/support/fake_thumbnail_renderer.dart — 05-library 5.7 (L0).
import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;

import 'package:note_core/note_core.dart';

/// A valid 1x1 PNG.
final Uint8List kTestPng1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Stand-in for INK's renderer behind pageThumbnailRendererProvider: records
/// every page it renders and can be told to wait, throw or return null.
final class FakeThumbnailRenderer implements PageThumbnailRenderer {
  /// Page ids in render order (a call counts when it starts, also when it
  /// then throws or returns null).
  final List<PageId> rendered = [];

  /// Awaited before every render (zero = no wait; use with fake_async).
  Duration delay = Duration.zero;

  /// Throws StateError for these pages (checked when a call starts).
  Set<PageId> failFor = {};

  /// Returns null for these pages (e.g. 'PDF bytes missing'; checked when a
  /// call starts).
  Set<PageId> nullFor = {};

  @override
  Future<PageThumbnail?> render(
    PageContent content, {
    int maxSidePx = 512,
  }) async {
    final page = content.page;
    rendered.add(page.id);
    // Decided when the call starts: a test may change the sets while this
    // render waits for [delay] (the L11 race tests rely on it).
    final fail = failFor.contains(page.id);
    final giveNull = nullFor.contains(page.id);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (fail) throw StateError('FakeThumbnailRenderer: failFor ${page.id}');
    if (giveNull) return null;
    return PageThumbnail(
      pageId: page.id,
      contentRevision: page.contentRevision,
      width: 1,
      height: 1,
      mimeType: 'image/png',
      bytes: kTestPng1x1,
    );
  }
}
