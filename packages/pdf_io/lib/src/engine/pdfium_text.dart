// lib/src/engine/pdfium_text.dart — what the engine adapter changes in PDFium's page text before
// anyone reads it (contract v2.6 C26-04; m5-7/06-pdf 6.4.5). src only (not in the barrel).
//
// PDFium joins a word hyphenated at a line end ('IN-' / 'DEXING') into one run with no line
// break and puts U+0002 where the hyphen was ('IN\u0002DEXING' — FPDFText's "hyphen at a line
// end" mark; its char box is the hyphen glyph). CORE's search normalisation (SearchText,
// contract 7.2.5) does not know U+0002, so neither the 1차 searchNote nor the v2 index found
// 'indexing'. The adapter hands it on as U+00AD SOFT HYPHEN instead, which CORE already drops:
// one UTF-16 unit for one, so the char boxes stay one per code unit (PdfPageTextData.charRects).
// Only a U+0002 between two word characters (letters, marks or digits) is changed — anything
// else is left as PDFium gave it. CORE's normalisation is not changed (C26-04).

/// U+0002 that PDFium puts between the two halves of a word hyphenated at a line end.
const String pdfiumHyphenJoin = '\u0002';

/// U+00AD SOFT HYPHEN — what the adapter puts in its place (CORE's normalisation drops it).
const String softHyphen = '­';

final RegExp _joinBetweenWordCharacters = RegExp(
  r'(?<=[\p{L}\p{M}\p{N}])\u0002(?=[\p{L}\p{M}\p{N}])',
  unicode: true,
);

/// [text] with each U+0002 between two word characters replaced by U+00AD (same length — the
/// code units around it keep their indexes).
String softenPdfiumHyphenJoins(String text) => text.contains(pdfiumHyphenJoin)
    ? text.replaceAll(_joinBetweenWordCharacters, softHyphen)
    : text;
