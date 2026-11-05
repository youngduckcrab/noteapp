@TestOn('browser')
library;

// T19 (03-ink 4.9, 6.13, 9.1): in Chrome the platform default is the web
// config (chunk 128 pt, outline 32 MB, raster 96 MB), and the render config
// tests hold there too.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';

import '../unit/render/render_config_test.dart' as render_config;

void main() {
  test('platformDefault == webDefaults in the browser', () {
    expect(InkRenderConfig.platformDefault, InkRenderConfig.webDefaults);
    expect(InkRenderConfig.platformDefault.chunkSizePt, 128);
  });

  group('render_config_test', render_config.main);
}
