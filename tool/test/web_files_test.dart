// The committed web files (docs/plans/01-infra.md 6.9, 9.1; contract
// 00-overview 7.4.9): manifest.json fields and icon paths, index.html metas,
// CSS, loader, viewport rewrite, gesture and contextmenu guards, and the
// custom flutter_bootstrap.js. Also the icon generator (tool/gen_icons.dart):
// sizes, safe zone and that the committed PNGs are its current output.
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../gen_icons.dart';
import '../src/png_size.dart';
import 'support/fixture_workspace.dart';

String get _web => p.join(repoRoot, 'app', 'web');

String _read(String name) => File(p.join(_web, name)).readAsStringSync();

/// The text between `<head>` and `</head>`.
String _head(String html) =>
    html.substring(html.indexOf('<head>'), html.indexOf('</head>'));

void main() {
  group('manifest.json', () {
    late Map<String, Object?> manifest;

    setUpAll(() {
      manifest = jsonDecode(_read('manifest.json')) as Map<String, Object?>;
    });

    test('fields of the 6.9 table', () {
      expect(manifest['id'], '/');
      expect(manifest['start_url'], '/');
      expect(manifest['scope'], '/');
      expect(manifest['name'], '필기노트 (테스트)');
      expect(manifest['short_name'], '필기노트');
      expect(manifest['display'], 'standalone');
      expect(manifest['orientation'], 'any');
      expect(manifest['background_color'], '#FFFFFF');
      expect(manifest['theme_color'], '#3949AB');
      expect(manifest['lang'], 'ko');
    });

    test('icons: 192 / 512 any + maskable, files exist with that size', () {
      final icons = (manifest['icons']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        icons.map((i) => (i['sizes'], i['purpose'])),
        unorderedEquals([
          ('192x192', 'any'),
          ('512x512', 'any'),
          ('192x192', 'maskable'),
          ('512x512', 'maskable'),
        ]),
      );
      for (final icon in icons) {
        final src = icon['src']! as String;
        expect(icon['type'], 'image/png', reason: src);
        final file = File(p.join(_web, src));
        expect(file.existsSync(), isTrue, reason: src);
        final size = pngSize(file.readAsBytesSync())!;
        expect('${size.width}x${size.height}', icon['sizes'], reason: src);
      }
    });
  });

  group('index.html', () {
    late String html;
    late String head;

    setUpAll(() {
      html = _read('index.html');
      head = _head(html);
    });

    test('document: lang ko, base href kept, charset, title', () {
      expect(html, contains('<html lang="ko">'));
      expect(head, contains(r'<base href="$FLUTTER_BASE_HREF">'));
      expect(head, contains('<meta charset="UTF-8">'));
      expect(head, contains('<title>필기노트</title>'));
    });

    test('PWA and iOS metas and links', () {
      for (final tag in [
        '<meta name="theme-color" content="#3949AB">',
        '<meta name="mobile-web-app-capable" content="yes">',
        '<meta name="apple-mobile-web-app-capable" content="yes">',
        '<meta name="apple-mobile-web-app-status-bar-style" content="default">',
        '<meta name="apple-mobile-web-app-title" content="필기노트">',
        '<meta name="format-detection" content="telephone=no">',
        '<link rel="apple-touch-icon" href="icons/Icon-180.png">',
        '<link rel="icon" type="image/png" href="favicon.png">',
        '<link rel="manifest" href="manifest.json">',
      ]) {
        expect(head, contains(tag));
      }
      for (final path in ['icons/Icon-180.png', 'favicon.png']) {
        expect(File(p.join(_web, path)).existsSync(), isTrue, reason: path);
      }
    });

    test('no CSP meta (contract 7.4.9)', () {
      expect(html.toLowerCase(), isNot(contains('content-security-policy')));
    });

    test('html, body CSS of the 6.9 table', () {
      final start = head.indexOf('html, body {');
      expect(start, isNonNegative);
      final rule = head.substring(start, head.indexOf('}', start));
      for (final declaration in [
        'margin: 0;',
        'height: 100%;',
        'overflow: hidden;',
        'overscroll-behavior: none;',
        'background: #FFFFFF;',
        '-webkit-user-select: none;',
        'user-select: none;',
        '-webkit-touch-callout: none;',
        '-webkit-tap-highlight-color: transparent;',
        '-webkit-text-size-adjust: 100%;',
        'touch-action: none;',
      ]) {
        expect(rule, contains(declaration));
      }
    });

    test(
      'viewport rewrite: MutationObserver on head with the fixed content',
      () {
        expect(head, contains('new MutationObserver('));
        expect(head, contains('.observe(document.head, { childList: true })'));
        expect(
          head,
          contains(
            "'width=device-width, initial-scale=1.0, maximum-scale=1.0, "
            "user-scalable=no'",
          ),
        );
        expect(head, contains("node.name === 'viewport'"));
      },
    );

    test('gesture events are cancelled with passive: false', () {
      for (final type in [
        'gesturestart',
        'gesturechange',
        'gestureend',
        'dblclick',
      ]) {
        expect(head, contains("'$type'"));
      }
      expect(head, contains('{ passive: false }'));
      expect(head, contains('event.preventDefault()'));
    });

    test('contextmenu guard keeps the menu inside text inputs', () {
      expect(head, contains("addEventListener('contextmenu'"));
      expect(
        head,
        contains(
          "'input, textarea, [contenteditable]:not([contenteditable=\"false\"])'",
        ),
      );
      expect(head, contains('target.closest(EDITABLE)'));
      expect(head, contains('if (!editable) event.preventDefault();'));
      // Not BrowserContextMenu.disableContextMenu() (contract 7.4.9 v1.1).
      expect(html, isNot(contains('disableContextMenu')));
    });

    test('loader: status text, first-frame removal, 30 s / error fallback '
        'with a reload button', () {
      expect(html, contains('<div id="app-loader"'));
      expect(html, contains('<div id="app-loader-status">불러오는 중…</div>'));
      expect(html, contains('<div id="app-loader-error"'));
      expect(html, contains('불러오지 못했어요'));
      expect(html, contains('>새로고침</button>'));
      expect(head, contains("'flutter-first-frame'"));
      expect(head, contains('30000'));
      expect(head, contains("addEventListener('error'"));
      expect(head, contains("addEventListener('unhandledrejection'"));
      expect(head, contains('window.location.reload()'));
    });

    test('noscript and the async bootstrap script', () {
      expect(html, contains('<noscript>'));
      expect(
        html,
        contains('<script src="flutter_bootstrap.js" async></script>'),
      );
    });
  });

  group('flutter_bootstrap.js', () {
    late String js;

    setUpAll(() => js = _read('flutter_bootstrap.js'));

    test('starts with the two build tokens', () {
      final lines = const LineSplitter().convert(js);
      expect(lines[0], '{{flutter_js}}');
      expect(lines[1], '{{flutter_build_config}}');
      // No other template variables (--web-define is not used).
      expect(RegExp(r'\{\{\w+\}\}').allMatches(js).map((m) => m.group(0)), [
        '{{flutter_js}}',
        '{{flutter_build_config}}',
      ]);
    });

    test('no service worker: none registered, old ones unregistered', () {
      expect(js, isNot(contains('serviceWorkerSettings')));
      expect(js, contains('navigator.serviceWorker.getRegistrations()'));
      expect(js, contains('registration.unregister()'));
    });

    test(
      'renderer choice: URL / localStorage, skwasm only with a wasm build',
      () {
        expect(js, contains("get('renderer')"));
        expect(js, contains("'noteapp.renderer'"));
        expect(js, contains("requested === 'default'"));
        expect(js, contains("build.compileTarget === 'dart2wasm'"));
        expect(
          js,
          contains(
            "{ renderer: 'skwasm', wasmAllowList: { blink: true, gecko: true, "
            'webkit: true } }',
          ),
        );
        expect(js, contains("{ renderer: 'canvaskit' }"));
      },
    );

    test('load → initializeEngine → runApp with status updates', () {
      expect(js, contains('_flutter.loader.load({'));
      expect(js, contains('onEntrypointLoaded'));
      expect(js, contains('initializeEngine()'));
      expect(js, contains('runApp()'));
      expect(js, contains("setStatus('엔진 준비 중…')"));
    });
  });

  group('icons (tool/gen_icons.dart)', () {
    test('every spec has its pixel size; names match R13', () {
      expect(iconSpecs.map((s) => s.path), [
        'favicon.png',
        'icons/Icon-180.png',
        'icons/Icon-192.png',
        'icons/Icon-512.png',
        'icons/Icon-maskable-192.png',
        'icons/Icon-maskable-512.png',
      ]);
      for (final spec in iconSpecs) {
        final size = pngSize(renderIcon(spec.size, maskable: spec.maskable))!;
        expect(size.width, spec.size, reason: spec.path);
        expect(size.height, spec.size, reason: spec.path);
      }
      expect(iconSpecs.first.size, 32);
    });

    test('the committed PNGs are the generator output', () {
      for (final spec in iconSpecs) {
        final committed = File(p.join(_web, spec.path)).readAsBytesSync();
        expect(
          committed,
          renderIcon(spec.size, maskable: spec.maskable),
          reason: '${spec.path}: run `dart run tool/gen_icons.dart`',
        );
      }
    });

    test('indigo background corners; maskable keeps the paper inside the '
        'safe zone', () {
      for (final maskable in [false, true]) {
        final icon = img.decodePng(renderIcon(512, maskable: maskable))!;
        final corner = icon.getPixel(2, 2);
        expect((corner.r, corner.g, corner.b), (0x39, 0x49, 0xAB));
        // White paper at the center.
        final center = icon.getPixel(256, 200);
        expect((center.r, center.g, center.b), (0xFF, 0xFF, 0xFF));
      }
      // Maskable: nothing white outside the central 80 % circle.
      final maskable = img.decodePng(renderIcon(512, maskable: true))!;
      for (final pixel in maskable) {
        final dx = pixel.x - 255.5;
        final dy = pixel.y - 255.5;
        if (dx * dx + dy * dy > 205 * 205) {
          expect(
            pixel.r < 0xF0 || pixel.b < 0xF0,
            isTrue,
            reason: 'white at (${pixel.x}, ${pixel.y})',
          );
        }
      }
    });

    test('--out writes every file', () {
      final dir = Directory.systemTemp.createTempSync('gen_icons_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final written = writeIcons(dir.path);
      expect(written, hasLength(iconSpecs.length));
      for (final spec in iconSpecs) {
        expect(File(p.join(dir.path, spec.path)).existsSync(), isTrue);
      }
    });
  });
}
