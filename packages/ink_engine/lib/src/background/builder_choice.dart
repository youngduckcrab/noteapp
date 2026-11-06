// lib/src/background/builder_choice.dart — INTERNAL. Builder selection (6.17): the first
// builder that handles the spec; otherwise the template builder paints the paper only
// (image / unknown, or pdf without a PDF builder). (m5-7 T35, 6.20) The image cache
// a page draws its image objects with is the one of the first image builder.
import '../image/image_cache.dart';
import 'background_builder.dart';
import 'background_spec.dart';
import 'image_builder.dart';
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

/// (m5-7 T35) The image cache of the first ImageBackgroundLayerBuilder in [builders]
/// (the page's image objects use it); null = none — image objects draw placeholders.
InkImageCache? imageCacheOf(List<PageBackgroundLayerBuilder> builders) {
  for (final b in builders) {
    if (b is ImageBackgroundLayerBuilder) return b.images;
  }
  return null;
}
