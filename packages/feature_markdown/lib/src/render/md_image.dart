// Images (08-markdown 8.3, B-5). Remote images are NEVER fetched (privacy, offline): a
// dashed placeholder with the alt text, the host and '이미지를 불러오지 않았어요'. Only
// `data:image/(png|jpeg|gif|webp);base64` up to 2 MB is drawn (decoded once while
// parsing). Relative paths name a file of the original that was not imported.
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../markdown_keys.dart';
import '../parse/md_model.dart';
import '../strings_ko.dart';
import 'md_inline.dart';

class MdImageView extends StatelessWidget {
  const MdImageView({super.key, required this.image, this.inline = false});

  final MdImage image;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final bytes = image.bytes;
    final Widget child;
    if (image.source == MdImageSource.data && bytes != null) {
      child = Semantics(
        image: true,
        label: image.alt.isEmpty ? MdStrings.image : image.alt,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: inline ? 120 : 480),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, _, _) => _Placeholder(
              image: image,
              message: MdStrings.imageUnsupported,
              inline: inline,
            ),
          ),
        ),
      );
    } else {
      child = _Placeholder(
        image: image,
        inline: inline,
        message: switch (image.source) {
          MdImageSource.remote => MdStrings.imageNotLoaded,
          MdImageSource.relative => MdStrings.imageRelative,
          _ => MdStrings.imageUnsupported,
        },
      );
    }
    return KeyedSubtree(key: MarkdownKeys.image(image.index), child: child);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.image,
    required this.message,
    required this.inline,
  });

  final MdImage image;
  final String message;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final s = MdRenderScope.of(context).style;
    final t = s.tokens;
    final alt = image.alt.trim().isEmpty ? MdStrings.image : image.alt.trim();
    final host = image.host;
    final label = [alt, if (host.isNotEmpty) host, message].join(', ');
    if (inline) {
      return Semantics(
        label: label,
        child: CustomPaint(
          painter: _DashedBorder(color: t.outline, radius: t.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIconKind.imageBlocked,
                  size: 16,
                  color: t.textSecondary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    alt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: s.small,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _DashedBorder(color: t.outline, radius: t.radiusMedium),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                AppIcon(
                  AppIconKind.imageBlocked,
                  size: 28,
                  color: t.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alt,
                        style: s.body.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      if (host.isNotEmpty)
                        Text(
                          host,
                          style: s.small,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(message, style: s.small),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.6),
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}
