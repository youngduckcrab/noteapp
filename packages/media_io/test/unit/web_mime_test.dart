// The web recorder's MIME table (m5-7/06-pdf 6.8.1 — 8.2 T32b): the choice for each support set,
// allowNonAacOnWeb, candidate 3 only without WebM, the actual MIME after start updating
// crossPlatformPlayable and the extension, the encoder line of the developer overlay (6.14).
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/record/web_mime.dart';

WebMimeTable table(Set<String> supported) =>
    WebMimeTable.probe(supported.contains);

const mp4a40 = 'audio/mp4;codecs=mp4a.40.2';
const mp4a = 'audio/mp4;codecs=mp4a';
const mp4 = 'audio/mp4';
const opus = 'audio/webm;codecs=opus';
const webm = 'audio/webm';

void main() {
  test('the candidates in 6.8.1 order', () {
    expect(webMimeCandidates, [mp4a40, mp4a, mp4, opus, webm]);
  });

  group('choose (6.8.1)', () {
    test('Safari (AAC with the codec named) → candidate 1, playable, .m4a', () {
      final c = table({mp4a40, mp4a, mp4}).choose(allowNonAacOnWeb: true);
      expect(
        c,
        const WebMimeChoice(
          mimeType: mp4a40,
          crossPlatformPlayable: true,
          extension: '.m4a',
        ),
      );
    });

    test('only mp4a → candidate 2', () {
      expect(
        table({mp4a, mp4, opus}).choose(allowNonAacOnWeb: true)?.mimeType,
        mp4a,
      );
    });

    test('Linux Chrome (mp4 + webm, no mp4a) → candidate 4, not 3', () {
      final c = table({mp4, opus, webm}).choose(allowNonAacOnWeb: true);
      expect(
        c,
        const WebMimeChoice(
          mimeType: opus,
          crossPlatformPlayable: false,
          extension: '.webm',
        ),
      );
    });

    test('mp4 without a codec only when the browser has no WebM (old Safari)', () {
      final c = table({mp4}).choose(allowNonAacOnWeb: true);
      expect(c?.mimeType, mp4);
      expect(c?.crossPlatformPlayable, isTrue);
      expect(c?.extension, '.m4a');
      // also with allowNonAacOnWeb false — it is AAC as far as the browser says
      expect(table({mp4}).choose(allowNonAacOnWeb: false)?.mimeType, mp4);
      // WebM support (4 or 5) rules candidate 3 out
      expect(table({mp4, webm}).choose(allowNonAacOnWeb: true)?.mimeType, webm);
    });

    test('allowNonAacOnWeb false: Chrome has nothing to record', () {
      expect(table({mp4, opus, webm}).choose(allowNonAacOnWeb: false), isNull);
      expect(table({opus}).choose(allowNonAacOnWeb: false), isNull);
      // AAC still wins
      expect(
        table({mp4a40, opus}).choose(allowNonAacOnWeb: false)?.mimeType,
        mp4a40,
      );
    });

    test('plain audio/webm when opus is not named', () {
      final c = table({webm}).choose(allowNonAacOnWeb: true);
      expect(c?.mimeType, webm);
      expect(c?.crossPlatformPlayable, isFalse);
      expect(c?.extension, '.webm');
    });

    test('nothing supported → null', () {
      expect(table({}).choose(allowNonAacOnWeb: true), isNull);
      expect(WebMimeTable(const {}).choose(allowNonAacOnWeb: true), isNull);
    });

    test('a throwing probe counts as not supported', () {
      final t = WebMimeTable.probe((m) {
        if (m == mp4a40) throw StateError('no');
        return m == opus;
      });
      expect(t.supported[mp4a40], isFalse);
      expect(t.choose(allowNonAacOnWeb: true)?.mimeType, opus);
    });
  });

  group('choiceForActual', () {
    const chromeMp4 = WebMimeChoice(
      mimeType: mp4,
      crossPlatformPlayable: true,
      extension: '.m4a',
    );

    test('mp4 that holds opus → not playable everywhere', () {
      final c = choiceForActual(chromeMp4, 'audio/mp4;codecs=opus');
      expect(c.mimeType, 'audio/mp4;codecs=opus');
      expect(c.crossPlatformPlayable, isFalse);
      expect(c.extension, '.m4a');
    });

    test('mp4 with AAC stays playable', () {
      final c = choiceForActual(chromeMp4, 'audio/mp4; codecs="mp4a.40.2"');
      expect(c.crossPlatformPlayable, isTrue);
      expect(c.extension, '.m4a');
    });

    test('an empty actual MIME keeps the chosen one', () {
      expect(choiceForActual(chromeMp4, ''), chromeMp4);
      expect(choiceForActual(chromeMp4, '  '), chromeMp4);
    });

    test('Chrome WebM: the actual MIME and .webm', () {
      final c = choiceForActual(
        const WebMimeChoice(
          mimeType: opus,
          crossPlatformPlayable: false,
          extension: '.webm',
        ),
        'audio/webm;codecs=opus',
      );
      expect(c.mimeType, 'audio/webm;codecs=opus');
      expect(c.crossPlatformPlayable, isFalse);
      expect(c.extension, '.webm');
    });
  });

  test('encoder line (6.14 enc: — web)', () {
    expect(
      table({mp4, opus, webm}).encoderLine,
      'mp4a=no mp4=yes webm/opus=yes',
    );
    expect(table({mp4a40, mp4}).encoderLine, 'mp4a=yes mp4=yes webm/opus=no');
    expect(table({mp4a}).encoderLine, 'mp4a=yes mp4=no webm/opus=no');
  });

  test('value equality of the table', () {
    expect(table({mp4, opus}), table({opus, mp4}));
    expect(table({mp4, opus}), isNot(table({mp4})));
  });
}
