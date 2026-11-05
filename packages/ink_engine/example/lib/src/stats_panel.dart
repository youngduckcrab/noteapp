// The developer numbers of ink lab (03-ink 4.12 InkDiagnostics.snapshot) —
// the values the 9.3 iPad checks read: raw pressure and capability, tilt,
// input Hz, samples per frame, latency and frame times, cache totals.
import 'package:ink_engine/ink_engine.dart';
import 'package:material_ui/material_ui.dart';

class InkStatsPanel extends StatelessWidget {
  const InkStatsPanel({super.key, required this.diagnostics});

  final InkDiagnostics diagnostics;

  static String _n(double? v, [int digits = 2]) =>
      v == null ? '–' : v.toStringAsFixed(digits);

  static String _ms(LatencySummary s) => s.count == 0
      ? '–'
      : '${_n(s.p50Ms, 1)} / ${_n(s.p95Ms, 1)} ms (${s.count})';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: diagnostics,
    builder: (context, _) {
      final s = diagnostics.snapshot;
      final mb = s.cache.totalBytes / (1024 * 1024);
      final lines = <(String, String)>[
        ('kind', s.lastKind?.name ?? '–'),
        ('rawPressure', _n(s.lastRawPressure, 3)),
        ('pressure', _n(s.lastNormalizedPressure, 3)),
        ('widthFactor', _n(s.lastWidthFactor)),
        ('source', s.pressureSource.name),
        ('stylusCapability', s.stylusCapability.name),
        ('tilt', _n(s.lastTilt)),
        ('orientation', _n(s.lastOrientation)),
        ('inputHz', _n(s.inputHz, 0)),
        ('samplesPerFrame', _n(s.samplesPerFrame)),
        ('eventToPaint p50/p95', _ms(s.eventToPaint)),
        ('eventToRasterEnd p50/p95', _ms(s.eventToRasterEnd)),
        (
          'frame build / raster p95',
          '${_n(s.frameBuildP95Ms, 1)} / '
              '${_n(s.frameRasterP95Ms, 1)} ms',
        ),
        ('tileRaster p50/p95', _ms(s.tileRaster)),
        ('visible strokes', '${s.visibleStrokeCount}'),
        (
          'cache',
          '${mb.toStringAsFixed(1)} MB, '
              '${s.cache.chunkPictures} pictures',
        ),
        ('clockAligned', '${s.clockAligned}'),
        ('warnings', '${s.warnings}'),
      ];
      final theme = Theme.of(context);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DefaultTextStyle(
            style: theme.textTheme.bodySmall!.copyWith(
              color: theme.colorScheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (label, value) in lines) Text('$label: $value'),
              ],
            ),
          ),
        ),
      );
    },
  );
}
