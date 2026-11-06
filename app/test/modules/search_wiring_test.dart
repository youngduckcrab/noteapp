// CORE search index → developer overlay (docs/plans/m5-7/01-infra.md 4.6.5,
// 6.7, S2-4): the 'search.index' section, its line format, and the lines'
// rate — the first status at once, then at most one update per 250 ms
// (≤ 4 Hz, the DevOverlaySection rule), the latest status winning. Time is
// fake_async only.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:feature_editor/feature_editor.dart' show DevOverlaySection;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/modules/search_wiring.dart';

/// A SearchIndex whose status stream the test drives.
final class _StatusIndex extends Fake implements SearchIndex {
  final StreamController<SearchIndexStatus> controller =
      StreamController<SearchIndexStatus>.broadcast();

  @override
  Stream<SearchIndexStatus> get status => controller.stream;

  Future<void> close() => controller.close();
}

String _line(int pending, {bool rebuilding = false, String last = '없음'}) =>
    '대기 $pending · ${rebuilding ? '재구축 중' : '대기'} · 마지막 재구축 $last';

void main() {
  group('formatSearchIndexStatus', () {
    test('before the first rebuild', () {
      expect(formatSearchIndexStatus(const SearchIndexStatus()), [_line(0)]);
      expect(
        formatSearchIndexStatus(
          const SearchIndexStatus(pendingOwners: 3, rebuilding: true),
        ),
        [_line(3, rebuilding: true)],
      );
    });

    test('the last rebuild in local time, MM-dd HH:mm:ss', () {
      final at = DateTime(2026, 11, 6, 9, 41, 5).millisecondsSinceEpoch;
      expect(
        formatSearchIndexStatus(
          SearchIndexStatus(pendingOwners: 2, lastRebuildAt: at),
        ),
        [_line(2, last: '11-06 09:41:05')],
      );
      final january = DateTime(2027, 1, 2, 3, 4, 5).millisecondsSinceEpoch;
      expect(
        formatSearchIndexStatus(SearchIndexStatus(lastRebuildAt: january)),
        [_line(0, last: '01-02 03:04:05')],
      );
    });
  });

  group('SearchIndexLines (≤ 4 Hz)', () {
    test('the default line before any status; the first status at once', () {
      fakeAsync((async) {
        final source = StreamController<SearchIndexStatus>();
        final lines = SearchIndexLines(source.stream);
        expect(lines.value, [_line(0)]);
        source.add(const SearchIndexStatus(pendingOwners: 1));
        async.flushMicrotasks();
        expect(lines.value, [_line(1)]);
        lines.dispose();
        unawaited(source.close());
        async.flushMicrotasks();
      });
    });

    test('a 100 Hz status stream → updates at least 250 ms apart, the latest '
        'status after the stream goes quiet', () {
      fakeAsync((async) {
        final source = StreamController<SearchIndexStatus>();
        final lines = SearchIndexLines(source.stream);
        final updates = <(Duration, List<String>)>[];
        lines.addListener(() => updates.add((async.elapsed, lines.value)));
        for (var i = 1; i <= 100; i++) {
          source.add(SearchIndexStatus(pendingOwners: i));
          async.elapse(const Duration(milliseconds: 10));
        }
        // 0 – 1000 ms: one update per started 250 ms.
        expect(
          updates.where((u) => u.$1 < const Duration(seconds: 1)),
          hasLength(4),
        );
        async.elapse(const Duration(milliseconds: 300));
        for (var i = 1; i < updates.length; i++) {
          expect(
            updates[i].$1 - updates[i - 1].$1,
            greaterThanOrEqualTo(SearchIndexLines.interval),
          );
        }
        expect(updates.first.$2, [_line(1)]);
        expect(lines.value, [_line(100)], reason: 'the latest status wins');
        final count = updates.length;
        async.elapse(const Duration(seconds: 5));
        expect(updates, hasLength(count), reason: 'quiet: no more updates');
        lines.dispose();
        unawaited(source.close());
        async.flushMicrotasks();
      });
    });

    test('a status after a quiet period shows at once again', () {
      fakeAsync((async) {
        final source = StreamController<SearchIndexStatus>();
        final lines = SearchIndexLines(source.stream);
        source.add(const SearchIndexStatus(pendingOwners: 1));
        async.elapse(const Duration(seconds: 1));
        source.add(const SearchIndexStatus(pendingOwners: 2));
        async.flushMicrotasks();
        expect(lines.value, [_line(2)]);
        lines.dispose();
        unawaited(source.close());
        async.flushMicrotasks();
      });
    });

    test('a stream error keeps the last line', () {
      fakeAsync((async) {
        final source = StreamController<SearchIndexStatus>();
        final lines = SearchIndexLines(source.stream);
        source.add(const SearchIndexStatus(pendingOwners: 4));
        async.flushMicrotasks();
        source.addError(StateError('index closed'));
        async.elapse(const Duration(seconds: 1));
        expect(lines.value, [_line(4)]);
        lines.dispose();
        unawaited(source.close());
        async.flushMicrotasks();
      });
    });

    test('dispose cancels the subscription and the pending update', () {
      fakeAsync((async) {
        final source = StreamController<SearchIndexStatus>.broadcast();
        final lines = SearchIndexLines(source.stream);
        source
          ..add(const SearchIndexStatus(pendingOwners: 1))
          ..add(const SearchIndexStatus(pendingOwners: 2));
        async.flushMicrotasks();
        expect(lines.value, [_line(1)]);
        lines.dispose();
        async.flushMicrotasks();
        expect(source.hasListener, isFalse);
        // The pending status (2) never lands on the disposed notifier.
        async.elapse(const Duration(seconds: 1));
        expect(async.pendingTimers, isEmpty);
        unawaited(source.close());
      });
    });
  });

  test('searchIndexSection: id search.index, title 검색 색인, lines over '
      'searchIndexProvider.status; disposed with its provider', () {
    fakeAsync((async) {
      final index = _StatusIndex();
      final section = Provider<DevOverlaySection>(
        searchIndexSection,
        name: '_searchSection',
      );
      final container = ProviderContainer.test(
        overrides: [searchIndexProvider.overrideWithValue(index)],
      );
      final value = container.read(section);
      expect((value.id, value.title), ('search.index', '검색 색인'));
      expect(value.lines, isA<SearchIndexLines>());
      expect(index.controller.hasListener, isTrue);
      index.controller.add(
        const SearchIndexStatus(pendingOwners: 5, rebuilding: true),
      );
      async.flushMicrotasks();
      expect(value.lines.value, [_line(5, rebuilding: true)]);

      container.dispose();
      async.flushMicrotasks();
      expect(index.controller.hasListener, isFalse);
      expect(
        () => (value.lines as ChangeNotifier).addListener(() {}),
        throwsFlutterError,
        reason: 'the lines were disposed with the provider',
      );
      unawaited(index.close());
      async.flushMicrotasks();
    });
  });
}
