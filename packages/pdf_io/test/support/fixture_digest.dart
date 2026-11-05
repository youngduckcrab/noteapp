// A fixed PdfFixtureBuilder output and its SHA-256, checked on the VM
// (unit/fixture_builder_bytes_test) and under dart2js (web/pure_logic_browser_test): the RC4
// and number formatting must give the same bytes on both (contract 7.4.8). Web-safe.
import 'dart:typed_data';

import 'package:pdf_io/testing.dart';

const String encryptedFixtureSha256 =
    '7b368e66304e2c3c8267ea9598e91bfda1bf0c8fc8c1e3e06fb817f15aa9cc4b';

Uint8List encryptedFixture() =>
    (PdfFixtureBuilder()
          ..addPage(
            const PdfFixturePage(
              texts: [PdfFixtureText('x'), PdfFixtureText('강의', mapped: true)],
            ),
          )
          ..encrypt(userPassword: 'pw'))
        .build();
