// lib/src/ui/layout/library_metrics.dart — 05-library 6.2 (every size and
// delay of the library screen, logical px).
abstract final class LibraryMetrics {
  static const double expandedBreakpoint = 1100;
  static const double mediumBreakpoint = 600;
  static const double sidebarWidth = 280;
  static const double drawerWidth = 320;
  static const double dividerWidth = 1;
  static const double topBarHeight = 64;

  /// Apple HIG.
  static const double minTapTarget = 44;

  /// Sidebar 홈 / 최근 / 즐겨찾기 / 휴지통.
  static const double navRowHeight = 44;
  static const double treeRowHeight = 44;
  static const double treeIndent = 16;

  /// Deeper rows stay at 8 * 16.
  static const int treeMaxIndentLevels = 8;
  static const double listRowHeight = 64;
  static const double trashRowHeight = 72;
  static const double gridPaddingRegular = 24, gridPaddingCompact = 16;
  static const double gridGapRegular = 20, gridGapCompact = 12;
  static const double minTileWidthRegular = 168, minTileWidthCompact = 140;
  static const int minColumns = 2;

  /// Width / height.
  static const double coverAspect = 3 / 4;

  /// 8 gap + 2 title lines (20) + meta line (16).
  static const double tileFooterBase = 64;
  static const double maxTileTextScale = 1.3;

  /// Gap between a grid tile's cover and its ⋯ button (next to the title).
  static const double tileMenuTopGap = 4;

  /// A ColorCover card narrower than this (list row thumbnail) shows no
  /// title (6.15.1).
  static const double coverTitleMinWidth = 96;
  static const double searchFieldWidthExpanded = 240,
      searchFieldWidthMedium = 200;
  static const double breadcrumbCrumbMaxWidth = 200;
  static const double dialogMaxWidth = 560;
  static const double pickerDialogMaxWidth = 480, pickerDialogMaxHeight = 600;

  /// Px from the viewport edge.
  static const double dragAutoScrollZone = 56;

  /// Px/s.
  static const double dragAutoScrollMaxSpeed = 1200;

  /// Px from the left screen edge.
  static const double drawerEdgeZone = 24;
  static const Duration longPressDelay = Duration(milliseconds: 400);
  static const Duration autoExpandDelay = Duration(milliseconds: 700);
  static const Duration drawerEdgeDelay = Duration(milliseconds: 600);
  static const Duration searchDebounce = Duration(milliseconds: 300);
  static const Duration undoSnackBarDuration = Duration(seconds: 6);
  static const Duration errorSnackBarDuration = Duration(seconds: 4);
  static const Duration expansionSaveDebounce = Duration(milliseconds: 500);

  /// Sidebar header (app name) and footer (sync status + settings) rows.
  static const double sidebarEdgeRowHeight = 56;
}
