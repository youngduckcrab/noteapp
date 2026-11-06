/// CORE search index → developer overlay (docs/plans/m5-7/01-infra.md 4.6.5,
/// S2-4).
library;

import 'dart:async';

import 'package:feature_editor/feature_editor.dart' show DevOverlaySection;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:note_core/note_core.dart'
    show SearchIndexStatus, searchIndexProvider;

/// DevOverlaySection(id: 'search.index', title: '검색 색인', lines: ≤ 4 Hz
/// lines over searchIndexProvider.status: '대기 n · 재구축 중|대기 · 마지막
/// 재구축 <시각|없음>')
DevOverlaySection searchIndexSection(Ref ref) {
  final lines = SearchIndexLines(ref.watch(searchIndexProvider).status);
  ref.onDispose(lines.dispose);
  return DevOverlaySection(id: 'search.index', title: '검색 색인', lines: lines);
}

/// One line per status, e.g. '대기 2 · 재구축 중 · 마지막 재구축 11-06 09:41:05'
/// (pending owners · '재구축 중' or '대기' · local time of the last rebuild,
/// '없음' before the first).
List<String> formatSearchIndexStatus(SearchIndexStatus status) {
  final last = status.lastRebuildAt;
  final state = status.rebuilding ? '재구축 중' : '대기';
  final when = last == null ? '없음' : _localTime(last);
  return ['대기 ${status.pendingOwners} · $state · 마지막 재구축 $when'];
}

String _localTime(int epochMillis) {
  final t = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// The lines of [searchIndexSection]: the first status at once, then at most
/// one update per 250 ms (the latest status wins). Cancels its subscription
/// on dispose.
final class SearchIndexLines extends ValueNotifier<List<String>> {
  SearchIndexLines(Stream<SearchIndexStatus> status)
    : super(formatSearchIndexStatus(const SearchIndexStatus())) {
    _subscription = status.listen(_onStatus, onError: (Object _) {});
  }

  static const Duration interval = Duration(milliseconds: 250);

  late final StreamSubscription<SearchIndexStatus> _subscription;
  Timer? _quiet;
  SearchIndexStatus? _pending;
  bool _disposed = false;

  void _onStatus(SearchIndexStatus status) {
    if (_disposed) return;
    if (_quiet != null) {
      _pending = status;
      return;
    }
    value = formatSearchIndexStatus(status);
    _quiet = Timer(interval, _onQuietEnd);
  }

  void _onQuietEnd() {
    _quiet = null;
    final pending = _pending;
    _pending = null;
    if (pending != null) _onStatus(pending);
  }

  @override
  void dispose() {
    _disposed = true;
    _quiet?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
