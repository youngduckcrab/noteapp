/// The app's one icon table (UI stage 2, 01-infra 16): one meaning = one
/// icon.
///
/// Every meaning the screens show as an icon is an [AppIconKind]. Each kind
/// has
///
/// * a Material Rounded glyph ([AppIconKind.material]) — what menus, dialogs
///   and list rows use (`Icon(kind.material)`); where the rounded glyph is a
///   solid shape the outlined one is taken, so menu rows keep the line
///   weight of the line icons, and
/// * for the ~40 kinds on the often-seen screens (editor toolbar, library top
///   bar and sidebar, settings categories) a hand-drawn line icon
///   ([AppIconKind.hasLineArt]) that [AppIcon] paints: 24-unit grid, round
///   caps and joins, stroke weight from [StyleTokens.iconStrokeWidth]
///   (크래프트 1.7, 미니멀 1.5, 스튜디오 1.6 at 22 px).
///
/// No image or font files: the line icons are [CustomPainter] paths.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'style_tokens.dart';

/// One meaning shown as an icon. The names are meanings, not shapes:
/// 'delete' and the trash section share [trash] (both put things in the
/// 휴지통), 'duplicate' is one glyph everywhere.
enum AppIconKind {
  // --- navigation / chrome --------------------------------------------------
  back(Icons.arrow_back_rounded, lineArt: true),
  close(Icons.close_rounded, lineArt: true),
  more(Icons.more_horiz_rounded, lineArt: true),
  sidebar(Icons.menu_rounded, lineArt: true),
  chevronRight(Icons.chevron_right_rounded, lineArt: true),
  chevronDown(Icons.expand_more_rounded, lineArt: true),

  /// ⌃ 메뉴 숨기기 (the toolbar slides up).
  hideMenu(Icons.expand_less_rounded, lineArt: true),
  search(Icons.search_rounded, lineArt: true),
  settings(Icons.settings_rounded, lineArt: true),
  info(Icons.info_outline_rounded, lineArt: true),
  share(Icons.share_rounded, lineArt: true),

  // --- editor tools ---------------------------------------------------------
  undo(Icons.undo_rounded, lineArt: true),
  redo(Icons.redo_rounded, lineArt: true),
  lasso(Icons.gesture_rounded, lineArt: true),
  shape(Icons.category_rounded, lineArt: true),
  text(Icons.title_rounded, lineArt: true),
  insert(Icons.add_box_rounded, lineArt: true),

  /// The folded toolbar's [⋯도구] (shape, text, insert, recording).
  moreTools(Icons.widgets_rounded, lineArt: true),

  /// Pages of the note (page panel, the '2 / 4' button).
  pages(Icons.auto_stories_rounded, lineArt: true),
  mic(Icons.mic_none_rounded, lineArt: true),

  /// The mic while this note records.
  micOn(Icons.mic_rounded, lineArt: true),
  math(Icons.functions_rounded, lineArt: true),
  textPen(Icons.edit_note_rounded),
  image(Icons.image_rounded, lineArt: true),

  // --- library --------------------------------------------------------------
  /// 모든 노트 (the library home).
  home(Icons.home_rounded, lineArt: true),
  recent(Icons.schedule_rounded, lineArt: true),
  favorite(Icons.star_outline_rounded, lineArt: true),
  favoriteOn(Icons.star_rounded, lineArt: true),

  /// 휴지통 and '삭제' (to the trash).
  trash(Icons.delete_outline_rounded, lineArt: true),
  folder(Icons.folder_rounded, lineArt: true),
  add(Icons.add_rounded, lineArt: true),
  select(Icons.check_circle_outline_rounded, lineArt: true),
  sort(Icons.sort_rounded, lineArt: true),
  viewGrid(Icons.grid_view_rounded, lineArt: true),
  viewList(Icons.view_list_rounded, lineArt: true),
  note(Icons.description_rounded, lineArt: true),
  newNote(Icons.note_add_outlined),
  newFolder(Icons.create_new_folder_outlined),
  rename(Icons.edit_outlined),
  duplicate(Icons.content_copy_rounded),
  move(Icons.drive_file_move_outline),
  exportPdf(Icons.picture_as_pdf_outlined),
  importPdf(Icons.upload_file_outlined),
  cover(Icons.image_outlined),
  restore(Icons.restore_from_trash_outlined),
  deleteForever(Icons.delete_forever_outlined),
  selectAll(Icons.select_all_rounded),
  deselect(Icons.deselect_rounded),

  // --- settings categories --------------------------------------------------
  /// 화면 스타일 (home / editor style).
  style(Icons.palette_outlined, lineArt: true),
  brightness(Icons.contrast_rounded, lineArt: true),
  storage(Icons.inventory_2_rounded, lineArt: true),

  /// 입력 (fingers, palm, gestures).
  input(Icons.touch_app_rounded, lineArt: true),

  /// 펜 (pen settings, 펜과 입력).
  pen(Icons.edit_rounded, lineArt: true),

  /// 새 노트 기본값.
  notebook(Icons.menu_book_rounded, lineArt: true),
  recognition(Icons.document_scanner_rounded, lineArt: true),
  developer(Icons.code_rounded, lineArt: true),
  features(Icons.toggle_on_rounded, lineArt: true),

  /// 도구 이름 (names on hover — '펜을 띄우면 이름 보기').
  hoverName(Icons.chat_bubble_outline_rounded, lineArt: true),

  /// 이전 판 DB 사본 (a copy of past data).
  history(Icons.history_rounded, lineArt: true),

  // --- menu-only ------------------------------------------------------------
  photos(Icons.photo_library_outlined),
  camera(Icons.photo_camera_outlined),
  files(Icons.folder_open_outlined),
  paste(Icons.content_paste_rounded),
  reveal(Icons.visibility_outlined),
  conceal(Icons.visibility_off_outlined),

  /// '팔레트로 떼어내기'.
  detach(Icons.open_in_new_rounded),

  /// '메뉴에 다시 붙이기'.
  dock(Icons.vertical_align_top_rounded),
  check(Icons.check_rounded),
  sortUp(Icons.arrow_upward_rounded),
  sortDown(Icons.arrow_downward_rounded),
  warning(Icons.warning_amber_rounded),
  error(Icons.error_outline_rounded);

  const AppIconKind(this.material, {this.lineArt = false});

  /// The Material Rounded glyph (menus, dialogs, rows; [AppIcon] for a kind
  /// without line art).
  final IconData material;

  /// Whether [AppIcon] paints a line icon for this kind.
  final bool lineArt;

  /// See [lineArt].
  bool get hasLineArt => lineArt;
}

/// An [AppIconKind] as a line icon (or its Material Rounded glyph when the
/// kind has no line art).
///
/// Size and colour default to the ambient [IconTheme] (so an [IconButton]'s
/// disabled and selected colours apply), the stroke weight to
/// [StyleTokens.iconStrokeWidth]. The weight is for a 22 px icon and scales
/// with [size].
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.kind, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.strokeWidth,
  });

  final AppIconKind kind;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  /// Overrides [StyleTokens.iconStrokeWidth].
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = this.size ?? iconTheme.size ?? 24;
    final color =
        this.color ?? iconTheme.color ?? StyleTokens.of(context).textPrimary;
    if (!kind.hasLineArt) {
      return Icon(
        kind.material,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      );
    }
    final stroke = strokeWidth ?? StyleTokens.of(context).iconStrokeWidth;
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        // Like Icon: in a box forced larger (an input's prefix, a tight
        // slot) the icon keeps its size, centred.
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: AppIconPainter(kind, color: color, strokeWidth: stroke),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<AppIconKind>('kind', kind));
  }
}

/// Paints the line art of a kind on a 24-unit grid scaled to the canvas
/// (square; the shorter side). [strokeWidth] is for a 22 px icon.
class AppIconPainter extends CustomPainter {
  const AppIconPainter(
    this.kind, {
    required this.color,
    this.strokeWidth = 1.7,
  });

  final AppIconKind kind;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final s = side / 24;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(s);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * (side / 22) / s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    _paintKind(canvas, p, fill);
    canvas.restore();
  }

  void _paintKind(Canvas canvas, Paint p, Paint fill) {
    void l(double a, double b, double c, double d) =>
        canvas.drawLine(Offset(a, b), Offset(c, d), p);
    void poly(List<double> xy, {bool close = false}) {
      final path = Path()..moveTo(xy[0], xy[1]);
      for (var i = 2; i < xy.length; i += 2) {
        path.lineTo(xy[i], xy[i + 1]);
      }
      if (close) path.close();
      canvas.drawPath(path, p);
    }

    void rr(double l, double t, double r, double b, double radius) => canvas
        .drawRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(radius)), p);

    switch (kind) {
      case AppIconKind.back:
        poly([15, 5, 8, 12, 15, 19]);
      case AppIconKind.close:
        l(6.5, 6.5, 17.5, 17.5);
        l(17.5, 6.5, 6.5, 17.5);
      case AppIconKind.more:
        for (final x in [5.5, 12.0, 18.5]) {
          canvas.drawCircle(Offset(x, 12), 1.55, fill);
        }
      case AppIconKind.sidebar:
        rr(3, 4.5, 21, 19.5, 2.5);
        l(9.5, 4.5, 9.5, 19.5);
      case AppIconKind.chevronRight:
        poly([10, 7, 15, 12, 10, 17]);
      case AppIconKind.chevronDown:
        poly([7, 10, 12, 15, 17, 10]);
      case AppIconKind.hideMenu:
        poly([7, 14, 12, 9, 17, 14]);
        l(5, 5, 19, 5);
      case AppIconKind.search:
        canvas.drawCircle(const Offset(10.5, 10.5), 6.3, p);
        l(15.3, 15.3, 20, 20);
      case AppIconKind.settings:
        final gear = Path();
        const n = 96;
        for (var i = 0; i <= n; i++) {
          final a = 2 * math.pi * i / n;
          final r = 7.4 + 1.25 * _tanh(3.2 * math.cos(8 * a));
          final o = Offset(12 + r * math.cos(a), 12 + r * math.sin(a));
          i == 0 ? gear.moveTo(o.dx, o.dy) : gear.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(gear..close(), p);
        canvas.drawCircle(const Offset(12, 12), 3, p);
      case AppIconKind.info:
        canvas.drawCircle(const Offset(12, 12), 8.5, p);
        l(12, 11, 12, 16.5);
        canvas.drawCircle(const Offset(12, 7.8), 1.1, fill);
      case AppIconKind.share:
        // Android's three linked dots (not the iOS box-and-arrow).
        canvas.drawCircle(const Offset(17, 5.5), 2.5, p);
        canvas.drawCircle(const Offset(6.5, 12), 2.5, p);
        canvas.drawCircle(const Offset(17, 18.5), 2.5, p);
        l(8.7, 10.7, 14.8, 6.9);
        l(8.7, 13.3, 14.8, 17.1);
      case AppIconKind.undo:
      case AppIconKind.redo:
        if (kind == AppIconKind.redo) {
          canvas.translate(24, 0);
          canvas.scale(-1, 1);
        }
        poly([8.5, 5.5, 4, 10, 8.5, 14.5]);
        canvas.drawPath(
          Path()
            ..moveTo(4.5, 10)
            ..lineTo(14, 10)
            ..arcToPoint(
              const Offset(14, 19.5),
              radius: const Radius.circular(4.75),
            )
            ..lineTo(9.5, 19.5),
          p,
        );
      case AppIconKind.lasso:
        final loop = Path()
          ..addOval(
            Rect.fromCenter(
              center: const Offset(12.5, 9.5),
              width: 16,
              height: 10.5,
            ),
          );
        for (final m in loop.computeMetrics()) {
          var d = 0.0;
          while (d < m.length) {
            canvas.drawPath(m.extractPath(d, math.min(d + 2.6, m.length)), p);
            d += 4.6;
          }
        }
        canvas.drawPath(
          Path()
            ..moveTo(8, 14.2)
            ..quadraticBezierTo(5.5, 17, 8.5, 18.5)
            ..quadraticBezierTo(10.5, 19.5, 8.5, 22),
          p,
        );
      case AppIconKind.shape:
        rr(3.5, 10, 13.5, 20, 1.5);
        canvas.drawCircle(const Offset(15, 9), 5.5, p);
      case AppIconKind.text:
        l(5.5, 6, 18.5, 6);
        l(12, 6, 12, 19);
        l(5.5, 6, 5.5, 8);
        l(18.5, 6, 18.5, 8);
        l(9.5, 19, 14.5, 19);
      case AppIconKind.insert:
        rr(4, 4, 20, 20, 4);
        l(12, 8.5, 12, 15.5);
        l(8.5, 12, 15.5, 12);
      case AppIconKind.moreTools:
        rr(4, 4, 10.5, 10.5, 1.8);
        canvas.drawCircle(const Offset(16.75, 7.25), 3.25, p);
        rr(4, 13.5, 10.5, 20, 1.8);
        l(16.75, 13.5, 16.75, 20);
        l(13.5, 16.75, 20, 16.75);
      case AppIconKind.pages:
        canvas.drawPath(
          Path()
            ..moveTo(5, 8)
            ..lineTo(5, 18.5)
            ..quadraticBezierTo(5, 21, 7.5, 21)
            ..lineTo(15, 21),
          p,
        );
        rr(8.5, 3, 19.5, 17.5, 2);
        l(11.5, 8, 16.5, 8);
        l(11.5, 11.5, 15, 11.5);
      case AppIconKind.mic:
      case AppIconKind.micOn:
        final body = RRect.fromLTRBR(
          9,
          3.5,
          15,
          14.5,
          const Radius.circular(3),
        );
        canvas.drawRRect(body, kind == AppIconKind.micOn ? fill : p);
        canvas.drawPath(
          Path()
            ..moveTo(6, 11)
            ..quadraticBezierTo(6, 17.5, 12, 17.5)
            ..quadraticBezierTo(18, 17.5, 18, 11),
          p,
        );
        l(12, 17.5, 12, 20.5);
        l(9, 20.5, 15, 20.5);
      case AppIconKind.math:
        poly([17.5, 5, 6.5, 5, 12.5, 12, 6.5, 19, 17.5, 19]);
      case AppIconKind.image:
        rr(3.5, 5, 20.5, 19, 2.5);
        canvas.drawCircle(const Offset(9, 10), 1.6, p);
        poly([4, 17.5, 9.5, 13, 13, 16, 16, 13.5, 20.5, 17.5]);
      case AppIconKind.home:
        canvas.drawPath(
          Path()
            ..moveTo(4, 10.5)
            ..lineTo(12, 4)
            ..lineTo(20, 10.5)
            ..lineTo(20, 19)
            ..quadraticBezierTo(20, 20, 19, 20)
            ..lineTo(5, 20)
            ..quadraticBezierTo(4, 20, 4, 19)
            ..close(),
          p,
        );
        poly([10, 20, 10, 14.5, 14, 14.5, 14, 20]);
      case AppIconKind.recent:
        canvas.drawCircle(const Offset(12, 12), 8, p);
        poly([12, 7.5, 12, 12, 15, 14]);
      case AppIconKind.history:
        canvas.drawPath(
          Path()..addArc(
            Rect.fromCircle(center: const Offset(12, 12), radius: 8),
            math.pi * 0.95,
            math.pi * 1.75,
          ),
          p,
        );
        poly([3.2, 8.6, 4.1, 12.4, 7.6, 11]);
        poly([12, 8, 12, 12, 14.8, 13.8]);
      case AppIconKind.favorite:
      case AppIconKind.favoriteOn:
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final r = i.isEven ? 8.3 : 3.7;
          final a = -math.pi / 2 + i * math.pi / 5;
          final o = Offset(12 + r * math.cos(a), 12.8 + r * math.sin(a));
          i == 0 ? star.moveTo(o.dx, o.dy) : star.lineTo(o.dx, o.dy);
        }
        star.close();
        if (kind == AppIconKind.favoriteOn) canvas.drawPath(star, fill);
        canvas.drawPath(star, p);
      case AppIconKind.trash:
        l(4.5, 7, 19.5, 7);
        poly([9, 7, 9.5, 4.5, 14.5, 4.5, 15, 7]);
        canvas.drawPath(
          Path()
            ..moveTo(6.5, 7)
            ..lineTo(7.5, 19.5)
            ..quadraticBezierTo(7.6, 20.5, 8.6, 20.5)
            ..lineTo(15.4, 20.5)
            ..quadraticBezierTo(16.4, 20.5, 16.5, 19.5)
            ..lineTo(17.5, 7),
          p,
        );
        l(10.3, 10.5, 10.5, 17);
        l(13.7, 10.5, 13.5, 17);
      case AppIconKind.folder:
        canvas.drawPath(
          Path()
            ..moveTo(3, 7)
            ..quadraticBezierTo(3, 5, 5, 5)
            ..lineTo(9, 5)
            ..lineTo(11, 7.5)
            ..lineTo(19, 7.5)
            ..quadraticBezierTo(21, 7.5, 21, 9.5)
            ..lineTo(21, 17.5)
            ..quadraticBezierTo(21, 19.5, 19, 19.5)
            ..lineTo(5, 19.5)
            ..quadraticBezierTo(3, 19.5, 3, 17.5)
            ..close(),
          p,
        );
      case AppIconKind.add:
        l(12, 5, 12, 19);
        l(5, 12, 19, 12);
      case AppIconKind.select:
        canvas.drawCircle(const Offset(12, 12), 8.5, p);
        poly([8, 12.3, 10.8, 15, 16, 9.5]);
      case AppIconKind.sort:
        l(4.5, 7, 19.5, 7);
        l(4.5, 12, 15, 12);
        l(4.5, 17, 10.5, 17);
      case AppIconKind.viewGrid:
        for (final (x, y) in [
          (4.0, 4.0),
          (13.0, 4.0),
          (4.0, 13.0),
          (13.0, 13.0),
        ]) {
          rr(x, y, x + 7, y + 7, 1.8);
        }
      case AppIconKind.viewList:
        for (final y in [6.0, 12.0, 18.0]) {
          canvas.drawCircle(Offset(5, y), 1.2, fill);
          l(9, y, 19.5, y);
        }
      case AppIconKind.note:
        canvas.drawPath(
          Path()
            ..moveTo(14, 3.5)
            ..lineTo(7, 3.5)
            ..quadraticBezierTo(5, 3.5, 5, 5.5)
            ..lineTo(5, 18.5)
            ..quadraticBezierTo(5, 20.5, 7, 20.5)
            ..lineTo(17, 20.5)
            ..quadraticBezierTo(19, 20.5, 19, 18.5)
            ..lineTo(19, 8.5)
            ..close(),
          p,
        );
        poly([14, 3.5, 14, 8.5, 19, 8.5]);
        l(8.5, 12.5, 15.5, 12.5);
        l(8.5, 16, 13.5, 16);
      case AppIconKind.style:
        // A palette: the paint board with a thumb hole and three dots.
        canvas.drawPath(
          Path()
            ..moveTo(12, 3.5)
            ..cubicTo(6.8, 3.5, 3.5, 7.3, 3.5, 12)
            ..cubicTo(3.5, 16.8, 7.3, 20.5, 12, 20.5)
            ..cubicTo(13.6, 20.5, 14, 19.4, 13.3, 18.2)
            ..cubicTo(12.5, 16.8, 13.4, 15.3, 15, 15.3)
            ..lineTo(17, 15.3)
            ..cubicTo(19.2, 15.3, 20.5, 13.8, 20.5, 11.6)
            ..cubicTo(20.5, 7, 16.7, 3.5, 12, 3.5)
            ..close(),
          p,
        );
        for (final o in const [
          Offset(8, 11.5),
          Offset(10.5, 7.5),
          Offset(15, 8),
        ]) {
          canvas.drawCircle(o, 1.25, fill);
        }
      case AppIconKind.brightness:
        canvas.drawCircle(const Offset(12, 12), 8.5, p);
        canvas.drawPath(
          Path()
            ..moveTo(12, 3.5)
            ..arcToPoint(
              const Offset(12, 20.5),
              radius: const Radius.circular(8.5),
            )
            ..close(),
          fill,
        );
      case AppIconKind.storage:
        rr(3.5, 4.5, 20.5, 9, 1.5);
        canvas.drawPath(
          Path()
            ..moveTo(5, 9)
            ..lineTo(5, 18.5)
            ..quadraticBezierTo(5, 20, 6.5, 20)
            ..lineTo(17.5, 20)
            ..quadraticBezierTo(19, 20, 19, 18.5)
            ..lineTo(19, 9),
          p,
        );
        l(10, 13, 14, 13);
      case AppIconKind.input:
        // A pointing finger.
        canvas.drawPath(
          Path()
            ..moveTo(9, 13.5)
            ..lineTo(9, 5.5)
            ..quadraticBezierTo(9, 4, 10.5, 4)
            ..quadraticBezierTo(12, 4, 12, 5.5)
            ..lineTo(12, 11)
            ..lineTo(16.5, 11.8)
            ..quadraticBezierTo(18.5, 12.2, 18.3, 14.2)
            ..lineTo(17.6, 18.5)
            ..quadraticBezierTo(17.3, 20.5, 15.3, 20.5)
            ..lineTo(11.5, 20.5)
            ..quadraticBezierTo(10.4, 20.5, 9.7, 19.6)
            ..lineTo(6.3, 15.4)
            ..quadraticBezierTo(5.6, 14.4, 6.6, 13.7)
            ..quadraticBezierTo(7.6, 13, 9, 14.2),
          p,
        );
      case AppIconKind.pen:
        poly([5, 19, 6, 15, 15.5, 5.5, 18.5, 8.5, 9, 18], close: true);
        l(13.5, 7.5, 16.5, 10.5);
      case AppIconKind.notebook:
        rr(5.5, 3, 19, 21, 2);
        l(9, 3, 9, 21);
        l(12, 8, 16, 8);
        l(12, 11, 16, 11);
      case AppIconKind.recognition:
        for (final (x, y, dx, dy) in [
          (4.0, 4.0, 1.0, 1.0),
          (20.0, 4.0, -1.0, 1.0),
          (4.0, 20.0, 1.0, -1.0),
          (20.0, 20.0, -1.0, -1.0),
        ]) {
          poly([x, y + 4 * dy, x, y, x + 4 * dx, y]);
        }
        canvas.drawPath(
          Path()
            ..moveTo(7.5, 14)
            ..cubicTo(9, 8, 11, 8, 11.5, 12)
            ..cubicTo(12, 16, 14, 16, 16.5, 10),
          p,
        );
      case AppIconKind.developer:
        poly([8.5, 7, 3.5, 12, 8.5, 17]);
        poly([15.5, 7, 20.5, 12, 15.5, 17]);
        l(13.5, 5, 10.5, 19);
      case AppIconKind.hoverName:
        canvas.drawPath(
          Path()
            ..moveTo(6, 4.5)
            ..lineTo(18, 4.5)
            ..quadraticBezierTo(20.5, 4.5, 20.5, 7)
            ..lineTo(20.5, 13)
            ..quadraticBezierTo(20.5, 15.5, 18, 15.5)
            ..lineTo(12, 15.5)
            ..lineTo(8, 19.5)
            ..lineTo(8, 15.5)
            ..lineTo(6, 15.5)
            ..quadraticBezierTo(3.5, 15.5, 3.5, 13)
            ..lineTo(3.5, 7)
            ..quadraticBezierTo(3.5, 4.5, 6, 4.5)
            ..close(),
          p,
        );
        l(7.5, 8.5, 16.5, 8.5);
        l(7.5, 11.5, 13, 11.5);
      case AppIconKind.features:
        rr(3, 7, 21, 17, 5);
        canvas.drawCircle(const Offset(16, 12), 2.6, fill);
      // Menu-only kinds draw their Material glyph (AppIcon never gets here).
      case AppIconKind.textPen ||
          AppIconKind.newNote ||
          AppIconKind.newFolder ||
          AppIconKind.rename ||
          AppIconKind.duplicate ||
          AppIconKind.move ||
          AppIconKind.exportPdf ||
          AppIconKind.importPdf ||
          AppIconKind.cover ||
          AppIconKind.restore ||
          AppIconKind.deleteForever ||
          AppIconKind.selectAll ||
          AppIconKind.deselect ||
          AppIconKind.photos ||
          AppIconKind.camera ||
          AppIconKind.files ||
          AppIconKind.paste ||
          AppIconKind.reveal ||
          AppIconKind.conceal ||
          AppIconKind.detach ||
          AppIconKind.dock ||
          AppIconKind.check ||
          AppIconKind.sortUp ||
          AppIconKind.sortDown ||
          AppIconKind.warning ||
          AppIconKind.error:
        break;
    }
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  @override
  bool shouldRepaint(AppIconPainter old) =>
      old.kind != kind || old.color != color || old.strokeWidth != strokeWidth;
}
