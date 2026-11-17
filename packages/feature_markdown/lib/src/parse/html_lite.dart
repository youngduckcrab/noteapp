// A small allow-list for raw HTML in markdown (08-markdown 8.2, review U10). HTML is never
// executed or laid out as HTML: `<br>` breaks the line, `<img>` follows the image rules
// (remote images are not fetched), `<b> <strong> <i> <em> <code> <sub> <sup> <kbd> <s>
// <del>` give their look, any other tag is dropped and its inner text kept; the text of
// `<script> <style> <iframe>` is dropped too. Comments disappear.
import 'package:meta/meta.dart';

import 'md_model.dart';

/// One tag of raw HTML.
@immutable
final class HtmlTag {
  const HtmlTag({
    required this.name,
    required this.closing,
    required this.selfClosing,
    required this.attributes,
  });

  /// Lower case ('' for a comment or a declaration).
  final String name;
  final bool closing;
  final bool selfClosing;
  final Map<String, String> attributes;

  static final RegExp _tag = RegExp(
    r'^<(/?)([A-Za-z][A-Za-z0-9-]*)([^>]*?)(/?)>$',
    dotAll: true,
  );
  static final RegExp _attr = RegExp(
    r'''([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''',
  );

  /// null when [raw] is not one tag (a comment, a declaration, text).
  static HtmlTag? parse(String raw) {
    final m = _tag.firstMatch(raw.trim());
    if (m == null) return null;
    final attributes = <String, String>{};
    for (final a in _attr.allMatches(m.group(3)!)) {
      attributes[a.group(1)!.toLowerCase()] = decodeEntities(
        a.group(2) ?? a.group(3) ?? a.group(4) ?? '',
      );
    }
    return HtmlTag(
      name: m.group(2)!.toLowerCase(),
      closing: m.group(1)!.isNotEmpty,
      selfClosing: m.group(4)!.isNotEmpty,
      attributes: attributes,
    );
  }

  /// The mark of an allowed styling tag.
  MdMark? get mark => switch (name) {
    'b' || 'strong' => MdMark.strong,
    'i' || 'em' => MdMark.em,
    's' || 'del' || 'strike' => MdMark.del,
    'code' || 'tt' => MdMark.code,
    'sub' => MdMark.sub,
    'sup' => MdMark.sup,
    'kbd' => MdMark.kbd,
    _ => null,
  };

  /// Tags whose inner text is dropped as well.
  bool get dropsContent =>
      name == 'script' || name == 'style' || name == 'iframe';

  /// Tags that end a line in an HTML block.
  bool get breaksLine => const {
    'br',
    'p',
    'div',
    'li',
    'tr',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'summary',
    'details',
    'ul',
    'ol',
    'table',
    'blockquote',
    'hr',
  }.contains(name);
}

final RegExp _entity = RegExp(
  r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z]+);',
);

const Map<String, String> _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': '\u00A0',
  'middot': '·',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
  'copy': '©',
};

/// `&amp;` `&#39;` `&#x2014;` and a few common names → characters (unknown names stay).
String decodeEntities(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(_entity, (m) {
    final body = m.group(1)!;
    if (body.startsWith('#')) {
      final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final code = int.tryParse(
        hex ? body.substring(2) : body.substring(1),
        radix: hex ? 16 : 10,
      );
      if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    }
    return _named[body] ?? m.group(0)!;
  });
}

/// The pieces of an HTML block: tags ([HtmlTag] or null for comments) and texts.
Iterable<({String? text, HtmlTag? tag})> htmlTokens(String raw) sync* {
  final token = RegExp(r'<!--[\s\S]*?-->|<[^<>]*>|[^<]+|<');
  for (final m in token.allMatches(raw)) {
    final s = m.group(0)!;
    if (s.startsWith('<!--')) continue;
    if (s.startsWith('<') && s.length > 1) {
      final tag = HtmlTag.parse(s);
      if (tag != null) {
        yield (text: null, tag: tag);
        continue;
      }
      if (s.startsWith('<!') || s.startsWith('<?')) continue;
    }
    yield (text: s, tag: null);
  }
}
