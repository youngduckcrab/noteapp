// lib/src/ui/layout/size_class.dart — 05-library 6.2.
import 'library_metrics.dart';

enum LibrarySizeClass { compact, medium, expanded }

/// width >= 1100 → expanded, >= 600 → medium, else compact.
LibrarySizeClass librarySizeClassFor(double width) {
  if (width >= LibraryMetrics.expandedBreakpoint) {
    return LibrarySizeClass.expanded;
  }
  if (width >= LibraryMetrics.mediumBreakpoint) return LibrarySizeClass.medium;
  return LibrarySizeClass.compact;
}

/// Visible breadcrumb crumbs (6.6): expanded 4, medium 3, compact 2.
int breadcrumbMaxVisibleFor(LibrarySizeClass sizeClass) => switch (sizeClass) {
  LibrarySizeClass.expanded => 4,
  LibrarySizeClass.medium => 3,
  LibrarySizeClass.compact => 2,
};
