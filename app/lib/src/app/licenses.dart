/// App-level LicenseRegistry entries (docs/plans/m5-7/01-infra.md 4.6.7,
/// 6.18; contract 7.4.5 v2.1 — CP5: the NoteSans OFL text is an asset of
/// ink_engine).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../errors/app_error_log.dart';

/// The OFL text INK ships next to the NoteSans font files.
const String noteSansLicenseAsset = 'packages/ink_engine/assets/fonts/OFL.txt';

/// The package name the license page lists the entry under.
const String noteSansLicenseName = 'NoteSans (Noto Sans KR subset)';

/// The on-device math model (ink_recognition's '기기에서 수식 인식' —
/// downloaded on demand by the apps, never on the web; the files and their
/// LICENSE / NOTICE are in hosting/models/pix2text-mfr-1.5-int8pc/).
const String mathModelLicenseName = 'Pix2Text MFR 1.5 (on-device math model)';

/// The model's MIT license and where it comes from (the NOTICE in short).
const String mathModelLicenseText = '''Pix2Text-MFR-1.5 by BreezeDeus — https://huggingface.co/breezedeus/pix2text-mfr-1.5 (revision 1cef9f0bdcd6a4c63df7de1311fb0894593340cc), https://github.com/breezedeus/Pix2Text. The encoder and decoder were dynamically quantized to int8 (per channel) by this app's developers; the tokenizer is unchanged.

MIT License

Copyright (c) BreezeDeus

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.''';

/// LicenseRegistry entry 'NoteSans (Noto Sans KR subset)' with the text of
/// 'packages/ink_engine/assets/fonts/OFL.txt' (12.2 CP5). Missing asset → no
/// entry, logged once.
///
/// The text is read only when the license page collects the entries (the
/// registry is lazy), so start-up does not load the asset. [bundle] defaults
/// to rootBundle. Native apps also get the on-device math model's MIT
/// license ([mathModelLicenseName]).
void registerAppLicenses({AssetBundle? bundle, AppErrorLog? errorLog}) {
  var logged = false;
  LicenseRegistry.addLicense(() async* {
    final String text;
    try {
      text = await (bundle ?? rootBundle).loadString(noteSansLicenseAsset);
    } catch (error) {
      if (!logged) {
        logged = true;
        errorLog?.add(
          AppErrorRecord(
            time: DateTime.now(),
            source: AppErrorSource.manual,
            summary: 'NoteSans license text missing — no license entry',
            details: '$noteSansLicenseAsset: $error',
          ),
        );
      }
      return;
    }
    yield LicenseEntryWithLineBreaks(const [noteSansLicenseName], text);
  });
  // The apps only (the web build has no on-device math engine).
  if (!kIsWeb) {
    LicenseRegistry.addLicense(
      () => Stream.value(
        const LicenseEntryWithLineBreaks([
          mathModelLicenseName,
        ], mathModelLicenseText),
      ),
    );
  }
}
