// LibrarySection / LibrarySectionNotifier (05-library 6.3.3 / 6.4, 8 L4).
import 'package:feature_library/src/model/section.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_library_backend.dart';

void main() {
  late FakeLibraryBackend backend;
  late ProviderContainer container;

  setUp(() {
    backend = FakeLibraryBackend();
    container = ProviderContainer.test(overrides: backend.overrides);
  });
  tearDown(() => backend.dispose());

  /// Keeps the autoDispose instance for [routeFolderId] alive.
  LibrarySection Function() watch(String? routeFolderId) {
    final sub = container.listen(
      librarySectionProvider(routeFolderId),
      (_, _) {},
    );
    return sub.read;
  }

  group('value equality', () {
    test('every section kind', () {
      expect(const FolderSection('a'), const FolderSection('a'));
      expect(const FolderSection('a'), isNot(const FolderSection('b')));
      expect(const FolderSection(null), const FolderSection(null));
      expect(const FolderSection(null), isNot(const RecentSection()));
      expect(const RecentSection(), const RecentSection());
      expect(const FavoritesSection(), isNot(const TrashSection()));
      expect(
        const SearchSection('q', returnTo: RecentSection()),
        const SearchSection('q', returnTo: RecentSection()),
      );
      expect(
        const SearchSection('q', returnTo: RecentSection()),
        isNot(const SearchSection('q', returnTo: FolderSection(null))),
      );
      expect(
        const SearchSection('q', returnTo: RecentSection()).hashCode,
        const SearchSection('q', returnTo: RecentSection()).hashCode,
      );
    });
  });

  group('LibrarySectionNotifier', () {
    test('starts at the route folder; each route folder has its own state', () {
      final home = watch(null);
      final folder = watch('f1');
      expect(home(), const FolderSection(null));
      expect(folder(), const FolderSection('f1'));
      container.read(librarySectionProvider('f1').notifier).showTrash();
      expect(folder(), const TrashSection());
      expect(home(), const FolderSection(null));
    });

    test('recent, favorites, trash and back to the route folder', () {
      final section = watch('f1');
      final n = container.read(librarySectionProvider('f1').notifier);
      n.showRecent();
      expect(section(), const RecentSection());
      n.showFavorites();
      expect(section(), const FavoritesSection());
      n.showTrash();
      expect(section(), const TrashSection());
      n.showRouteFolder();
      expect(section(), const FolderSection('f1'));
    });

    test('search trims and remembers the section to return to', () {
      final section = watch('f1');
      final n = container.read(librarySectionProvider('f1').notifier);
      n.search('  수학 ');
      expect(
        section(),
        const SearchSection('수학', returnTo: FolderSection('f1')),
      );
      n.exitSearch();
      expect(section(), const FolderSection('f1'));
    });

    test('an empty search is exitSearch (no-op outside a search)', () {
      final section = watch(null);
      final n = container.read(librarySectionProvider(null).notifier);
      n.search('   ');
      expect(section(), const FolderSection(null));
      n.showRecent();
      n.search('a');
      n.search('');
      expect(section(), const RecentSection());
    });

    test('searching while searching replaces the query, keeps returnTo', () {
      final section = watch(null);
      final n = container.read(librarySectionProvider(null).notifier);
      n.showFavorites();
      n.search('a');
      n.search('ab');
      expect(
        section(),
        const SearchSection('ab', returnTo: FavoritesSection()),
      );
      n.search(' ');
      expect(section(), const FavoritesSection());
    });

    test('exitSearch outside a search does nothing', () {
      final section = watch(null);
      final n = container.read(librarySectionProvider(null).notifier);
      n.showTrash();
      n.exitSearch();
      expect(section(), const TrashSection());
    });

    test('leaving a search for another section drops it', () {
      final section = watch(null);
      final n = container.read(librarySectionProvider(null).notifier);
      n.search('a');
      n.showRecent();
      expect(section(), const RecentSection());
      n.exitSearch();
      expect(section(), const RecentSection());
    });
  });
}
