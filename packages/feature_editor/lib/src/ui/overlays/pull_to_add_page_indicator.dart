// lib/src/ui/overlays/pull_to_add_page_indicator.dart — 04-editor 6.11.7
// (당겨서 페이지 추가).
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../viewport/page_layout.dart';
import '../../viewport/viewport_constants.dart';
import '../../viewport/viewport_controller.dart';
import '../editor_strings.dart';

/// The strip a pull past the document end reveals (bottom edge of the page
/// area; right edge in the horizontal layout): '당겨서 페이지 추가' while
/// short of the threshold, '놓으면 페이지 추가' from it on (and while it
/// holds after such a release while the page is added). Starts at the
/// document end (a short document: not the viewport edge). Fades in with
/// the pull. Never takes input; hidden on a read-only note (no pull happens
/// there either).
class PullToAddPageIndicator extends ConsumerWidget {
  const PullToAddPageIndicator({super.key});

  static const indicatorKey = ValueKey('editor.pullToAddPage');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(editorReadOnlyProvider)) return const SizedBox.shrink();
    final viewport = ref.watch(editorViewportProvider);
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([viewport, viewport.pullPhase]),
        builder: (context, _) {
          final phase = viewport.pullPhase.value;
          final extent = viewport.pullExtent;
          if (phase == PullToAddPhase.idle || extent <= 0) {
            return const SizedBox.shrink();
          }
          final armed = phase != PullToAddPhase.pulling;
          final vertical = viewport.axis == LayoutAxis.vertical;
          final progress = (extent / ViewportConstants.pullToAddThreshold)
              .clamp(0.0, 1.0);
          final content = _Content(
            armed: armed,
            vertical: vertical,
            progress: progress,
            // Horizontal: the label wraps to the strip so it is not clipped.
            width: math.max(extent - 8, _minContentWidth),
          );
          final strip = ClipRect(
            child: OverflowBox(
              maxWidth: vertical ? null : double.infinity,
              maxHeight: vertical ? double.infinity : null,
              child: Center(
                child: Opacity(opacity: progress, child: content),
              ),
            ),
          );
          // Starts at the document end (the viewport edge unless a short
          // document sits centred).
          final edge = viewport.pullEdge;
          return Stack(
            children: [
              if (vertical)
                Positioned(
                  left: 0,
                  right: 0,
                  top: edge,
                  height: extent,
                  child: strip,
                )
              else
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: edge,
                  width: extent,
                  child: strip,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Narrowest horizontal content (a short pull shows the icon, faded).
const double _minContentWidth = 56;

class _Content extends StatelessWidget {
  const _Content({
    required this.armed,
    required this.vertical,
    required this.progress,
    required this.width,
  });

  final bool armed;
  final bool vertical;
  final double progress;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = armed ? scheme.primary : scheme.onSurfaceVariant;
    final label = armed
        ? EditorStrings.releaseToAddPage
        : EditorStrings.pullToAddPage;
    final icon = SizedBox.square(
      dimension: 28,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 2,
            color: color,
            backgroundColor: scheme.outlineVariant,
          ),
          Icon(
            armed
                ? Icons.add
                : (vertical ? Icons.arrow_upward : Icons.arrow_back),
            size: 16,
            color: color,
          ),
        ],
      ),
    );
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: theme.textTheme.labelLarge?.copyWith(color: color),
    );
    return Semantics(
      key: PullToAddPageIndicator.indicatorKey,
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: vertical
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [icon, const SizedBox(width: 8), text],
              )
            : SizedBox(
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [icon, const SizedBox(height: 8), text],
                ),
              ),
      ),
    );
  }
}
