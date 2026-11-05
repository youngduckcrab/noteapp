// CORE T18 — 9.1 budget: the first watchListing value with 200 folders and 1,000
// notes at the top level, < 100 ms.
@TestOn('vm')
@Tags(['perf'])
library;

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

import 'perf_support.dart';

void main() {
  test(
    'watchListing first value, 200 folders + 1,000 notes: < 100 ms',
    () async {
      final store = await openFileStore(await tempDatabasePath('listing'));
      // Queued together: the write queue batches them into few transactions.
      await Future.wait([
        for (var i = 0; i < 200; i++) store.library.createFolder(name: '폴더 $i'),
      ]);
      await Future.wait([
        for (var i = 0; i < 1000; i++)
          store.library.createNote(title: '노트 $i 강의'),
      ]);
      await store.library.watchListing(const LibraryQuery()).first; // warm-up

      final runs = <Duration>[];
      for (final query in const [
        LibraryQuery(),
        LibraryQuery(sort: LibrarySortField.name, descending: false),
        LibraryQuery(sort: LibrarySortField.createdAt),
        LibraryQuery(sort: LibrarySortField.custom),
        LibraryQuery(sort: LibrarySortField.name),
      ]) {
        final (listing, time) = await timed(
          () => store.library.watchListing(query).first,
        );
        expect(listing.folders, hasLength(200));
        expect(listing.notes, hasLength(1000));
        runs.add(time);
      }
      record(
        'watchListing first value 200 + 1,000 (median of 5 sorts)',
        median(runs),
        budget: const Duration(milliseconds: 100),
        note: 'runs ${[for (final r in runs) ms(r)]}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
