// lib/src/background/builder_choice.dart — INTERNAL. Builder selection (6.17): the first
// builder that handles the spec; otherwise the template builder paints the paper only
// (image / unknown, or pdf without a PDF builder).
import 'background_builder.dart';
import 'background_spec.dart';
import 'template_builder.dart';

PageBackgroundLayerBuilder backgroundBuilderFor(
  List<PageBackgroundLayerBuilder> builders,
  InkBackgroundSpec spec,
) {
  for (final b in builders) {
    if (b.handles(spec)) return b;
  }
  return const TemplateBackgroundLayerBuilder();
}

/// The first builder that handles [spec] AND is a still renderer (thumbnails, 6.17 step 2).
PageBackgroundStillRenderer? stillRendererFor(
  List<PageBackgroundLayerBuilder> builders,
  InkBackgroundSpec spec,
) {
  for (final b in builders) {
    if (b.handles(spec) && b is PageBackgroundStillRenderer) {
      return b as PageBackgroundStillRenderer;
    }
  }
  return null;
}
