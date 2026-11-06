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

/// LicenseRegistry entry 'NoteSans (Noto Sans KR subset)' with the text of
/// 'packages/ink_engine/assets/fonts/OFL.txt' (12.2 CP5). Missing asset → no
/// entry, logged once.
///
/// The text is read only when the license page collects the entries (the
/// registry is lazy), so start-up does not load the asset. [bundle] defaults
/// to rootBundle.
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
}
