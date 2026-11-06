// lib/src/text/text_box_placement.dart — m5-7/04-editor 6.11.1 (E2-01).
//
// Where a new text box goes: the tap rule of 6.11.1 (top-left = the point,
// width = min(240, page right − x − 16), at least 40 pt — pushed left when
// there is no room) and the developer menu's '텍스트 상자 시험' (a new box
// session at the centre of the visible part of the current page, so the
// session runs before the text tool exists — E2-03, review S-3).
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:note_core/note_core.dart' as core;

import '../viewport/viewport_controller.dart';
import 'text_edit_session.dart';

/// 6.11.1 numbers (pt).
abstract final class TextBoxPlacement {
  /// Width of a box started by a tap.
  static const double tapWidth = 240;

  /// Space kept between a tapped box and the page's right edge.
  static const double rightMargin = 16;

  /// The narrowest box.
  static const double minWidth = 40;
}

/// A new (not yet stored) text box whose top-left is [point] (page pt) on a
/// page [pageWidth] wide: width = min(240, pageWidth − x − 16), at least 40 —
/// when that does not fit, the box moves left (never past the page's left
/// edge). Height = one line of [style] (the session measures it).
core.TextBoxObject newTextBoxAt({
  required String id,
  required String pageId,
  required Offset point,
  required double pageWidth,
  required core.TextBoxStyle style,
  required core.EpochMillis createdAt,
}) {
  var x = point.dx;
  var width = math.min(
    TextBoxPlacement.tapWidth,
    pageWidth - x - TextBoxPlacement.rightMargin,
  );
  if (width < TextBoxPlacement.minWidth) {
    width = TextBoxPlacement.minWidth;
    x = math.max(
      0,
      pageWidth - TextBoxPlacement.rightMargin - TextBoxPlacement.minWidth,
    );
  }
  return core.TextBoxObject(
    id: id,
    pageId: pageId,
    frame: core.ElementFrame(
      core.PageRect.fromLTWH(
        x,
        point.dy,
        width,
        style.fontSizePt * style.lineHeight,
      ),
    ),
    text: '',
    style: style,
    createdAt: createdAt,
  );
}

/// The page point at the centre of the visible part of page [index] (the
/// page centre when none of it is on screen).
Offset visibleCentreOfPage(ViewportController viewport, int index) {
  final page = viewport.pageRectOnScreen(index);
  final screen = Offset.zero & viewport.viewportSize;
  final visible = page.intersect(screen);
  final centre = visible.width > 0 && visible.height > 0
      ? visible.center
      : page.center;
  return viewport.screenToPage(index, centre);
}

/// Developer menu '텍스트 상자 시험' (6.11.1, key editor.dev.textBoxProbe): a
/// new-box session at the centre of the visible part of the current page,
/// placed by the tap rule, default TextBoxStyle (ToolOptions comes in E2-03).
/// No-op before the viewport has pages.
void startTextBoxProbe({
  required ViewportController viewport,
  required TextEditNotifier notifier,
  required String Function() newId,
  required core.EpochMillis now,
}) {
  final pages = viewport.pages;
  if (pages.isEmpty || viewport.viewportSize.isEmpty) return;
  final index = viewport.currentPageIndex.value.clamp(0, pages.length - 1);
  final page = pages[index];
  final box = newTextBoxAt(
    id: newId(),
    pageId: page.id,
    point: visibleCentreOfPage(viewport, index),
    pageWidth: page.size.width,
    style: const core.TextBoxStyle(),
    createdAt: now,
  );
  notifier.start(box, isNew: true);
}
