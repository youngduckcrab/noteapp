// PdfFixtureBuilder byte layout without PDFium (06-pdf 4.14, 8 T2): deterministic output,
// one shared Helvetica, classic xref offsets, encryption dictionary.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/testing.dart';

import '../support/fixture_digest.dart';

String _text(List<int> bytes) => latin1.decode(bytes);

int _count(String haystack, String needle) =>
    needle.allMatches(haystack).length;

void main() {
  test('starts with %PDF-1.4, ends with %%EOF, deterministic', () {
    PdfFixtureBuilder make() =>
        PdfFixtureBuilder()
          ..addPages(3, (i) => PdfFixturePage(texts: [PdfFixtureText('p$i')]));
    final a = make().build();
    final b = make().build();
    expect(_text(a.sublist(0, 8)), '%PDF-1.4');
    expect(_text(a).trimRight(), endsWith('%%EOF'));
    expect(a, b);
  });

  test('one shared Helvetica for all pages', () {
    final pdf = _text(
      (PdfFixtureBuilder()..addPages(
            50,
            (i) => PdfFixturePage(texts: [PdfFixtureText('Page $i')]),
          ))
          .build(),
    );
    expect(_count(pdf, '/BaseFont /Helvetica'), 1);
    expect(_count(pdf, '/Type /Page '), 50);
    expect(_count(pdf, '/F1 3 0 R'), 50);
  });

  test('xref offsets point at the objects', () {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(const PdfFixturePage(rotate: 90))
              ..addPage(
                const PdfFixturePage(
                  texts: [PdfFixtureText('강의', mapped: true)],
                ),
              ))
            .build();
    final pdf = _text(bytes);
    final startxref = int.parse(
      RegExp(r'startxref\n(\d+)').firstMatch(pdf)!.group(1)!,
    );
    expect(pdf.substring(startxref, startxref + 4), 'xref');
    final entries = RegExp(r'(\d{10}) 00000 n ').allMatches(pdf).toList();
    for (var i = 0; i < entries.length; i++) {
      final offset = int.parse(entries[i].group(1)!);
      expect(pdf.substring(offset), startsWith('${i + 1} 0 obj'));
    }
    expect(pdf, contains('/Rotate 90'));
    expect(pdf, contains('/ToUnicode 5 0 R'));
    expect(pdf, contains('<21> <ac15>'));
  });

  test('encryption adds /Encrypt, /ID and the R2 dictionary', () {
    final pdf = _text(
      (PdfFixtureBuilder()
            ..addPage(const PdfFixturePage(texts: [PdfFixtureText('Secret')]))
            ..encrypt(userPassword: 'pw'))
          .build(),
    );
    expect(pdf, contains('/Filter /Standard /V 1 /R 2'));
    expect(pdf, contains('/P -4'));
    expect(pdf, contains('/Encrypt 6 0 R /ID [<'));
    // Content streams are encrypted: the plain text is gone.
    expect(pdf, isNot(contains('(Secret)')));
    final permissionOnly = _text(
      (PdfFixtureBuilder()
            ..addPage(const PdfFixturePage())
            ..encrypt(userPassword: ''))
          .build(),
    );
    expect(permissionOnly, contains('/P -44'));
  });

  test('invalid input is rejected', () {
    expect(() => PdfFixtureBuilder().build(), throwsStateError);
    expect(
      () => (PdfFixtureBuilder()..addPage(const PdfFixturePage(rotate: 45)))
          .build(),
      throwsArgumentError,
    );
    expect(
      () =>
          (PdfFixtureBuilder()
                ..addPage(const PdfFixturePage(texts: [PdfFixtureText('강의')])))
              .build(),
      throwsArgumentError,
    );
  });

  test(
    'a fixed encrypted fixture has the same digest on the VM and the web',
    () {
      expect(
        sha256.convert(encryptedFixture()).toString(),
        encryptedFixtureSha256,
      );
    },
  );
}
