// lib/src/document/mounted_pages.dart — 04-editor 6.4.4 (E-04).
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'page_mount.dart';

/// Per note (scoped). Lookup used by InteractionHost and EditorCommands: only mounted
/// pages can receive tool input (contract E-2).
///
/// Pages register from EditorPageView.initState and unregister from its
/// dispose, i.e. while the widget tree is building. Listeners are therefore
/// notified one microtask later (coalesced), never from inside a build.
final class MountedPages extends ChangeNotifier {
  final Map<String, PageMount> _mounts = {};
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Adds [mount] (replaces an earlier mount of the same page).
  void register(PageMount mount) {
    if (_disposed) return;
    _mounts[mount.pageId] = mount;
    _scheduleNotify();
  }

  /// Removes the mount of [pageId] (no-op when none).
  void unregister(String pageId) {
    if (_disposed) return;
    if (_mounts.remove(pageId) != null) _scheduleNotify();
  }

  PageMount? operator [](String pageId) => _mounts[pageId];

  Iterable<PageMount> get all => _mounts.values;

  /// Page ids of the mounted pages (registration order).
  Iterable<String> get pageIds => _mounts.keys;

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _mounts.clear();
    super.dispose();
  }
}
