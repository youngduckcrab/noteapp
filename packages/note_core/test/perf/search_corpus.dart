// Synthetic search corpora of the CORE T33b performance tests (not a test file — m5-7/02-core
// 6.10.7, 6.19): fixed seeds, Hangul words built from 400 syllables in a Zipf-like draw, Latin
// words, and pdf pages of a note library whose backgrounds show one asset's pages.
import 'dart:math';

import 'package:note_core/note_core.dart';

/// 400 Hangul syllables (no final consonant every 28th code point, then with finals).
final List<String> kSyllables = [
  for (var i = 0; i < 400; i++) String.fromCharCode(0xAC00 + i * 27),
];

/// A vocabulary of [size] words: 2–3 syllable Hangul words, or Latin words ([latinShare]).
List<String> vocabulary(Random r, {int size = 4000, double latinShare = 0}) => [
  for (var i = 0; i < size; i++)
    if (r.nextDouble() < latinShare)
      String.fromCharCodes([
        for (var k = 0, n = 3 + r.nextInt(6); k < n; k++) 97 + r.nextInt(26),
      ])
    else
      [
        for (var k = 0, n = 2 + r.nextInt(2); k < n; k++)
          kSyllables[(pow(r.nextDouble(), 2) * kSyllables.length).floor()],
      ].join(),
];

/// A word of [vocab], frequent words first (Zipf-like).
String draw(Random r, List<String> vocab) =>
    vocab[(pow(r.nextDouble(), 3) * vocab.length).floor()];

/// Text of [words] words of [vocab] separated by spaces.
String words(Random r, List<String> vocab, int words) =>
    [for (var i = 0; i < words; i++) draw(r, vocab)].join(' ');

/// Text of about [chars] UTF-16 code units, lines of about 50.
String pageText(Random r, List<String> vocab, int chars) {
  final b = StringBuffer();
  var line = 0;
  while (b.length < chars) {
    final w = draw(r, vocab);
    if (line + w.length > 50) {
      b.write('\n');
      line = 0;
    } else if (b.isNotEmpty) {
      b.write(' ');
      line++;
    }
    b.write(w);
    line += w.length;
  }
  return b.toString().substring(0, chars);
}

/// One glyph box per code unit of [text] (rows of 50 per line), fractions of the page.
List<PageRect> glyphBoxes(String text) {
  final out = <PageRect>[];
  var row = 0, col = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n') {
      out.add(PageRect.zero);
      row++;
      col = 0;
      continue;
    }
    final top = 0.05 + row * 0.018;
    out.add(
      PageRect(0.05 + col * 0.018, top, 0.068 + col * 0.018, top + 0.016),
    );
    col++;
  }
  return out;
}

/// Notes of [pagesPerNote] pages each showing pages 0..[pages]-1 of [assetId].
Future<void> pdfLibrary(
  NoteStore store,
  String assetId, {
  required int pages,
  int pagesPerNote = 100,
}) async {
  for (var start = 0; start < pages; start += pagesPerNote) {
    await store.library.createNote(
      title: 'pdf $start',
      pages: [
        for (var i = start; i < start + pagesPerNote && i < pages; i++)
          PageDraft(
            size: const PageSize(595, 842),
            background: PdfBackground(assetId: assetId, pdfPageIndex: i),
          ),
      ],
    );
  }
}
