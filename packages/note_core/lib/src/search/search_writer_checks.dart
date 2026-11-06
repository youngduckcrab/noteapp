// Internal (not exported) — the SearchIndexWriter validation of m5-7/02-core 6.10.3, shared by
// the real index (storage/drift_search_index.dart) and the fake store's memory index: any
// violation is an ArgumentError and nothing changes.
import '../common/ids.dart';
import 'search_types.dart';

final RegExp _pdfOwnerKey = RegExp(r'^[0-9a-f]{64}#[0-9]+$');

/// At most this many units per owner, this many chars per body, this many chars per sourceRev.
const int kSearchMaxUnitsPerOwner = 10000;
const int kSearchMaxBodyChars = 200000;
const int kSearchMaxSourceRevChars = 200;

/// Fractions may exceed [0, 1] by this much (then they are clamped when stored).
const double kSearchFractionSlack = 1e-6;

/// The writer accepts pdf owners only: ink / text / math are indexed by CORE itself
/// (contract 7.2.5), and a pdf owner key is `<assetId>#<pdfPageIndex>`.
void checkSearchWriterOwner(SearchSource source, String ownerKey) {
  if (source != SearchSource.pdf) {
    throw ArgumentError.value(
      source,
      'source',
      'only pdf is written through SearchIndexWriter (CORE indexes ink / text / math)',
    );
  }
  if (!_pdfOwnerKey.hasMatch(ownerKey)) {
    throw ArgumentError.value(
      ownerKey,
      'ownerKey',
      "must be '<assetId>#<pdfPageIndex>'",
    );
  }
}

/// The units and sourceRev of a replaceUnits call.
void checkSearchUnits(List<SearchUnitDraft> units, String sourceRev) {
  if (sourceRev.isEmpty || sourceRev.length > kSearchMaxSourceRevChars) {
    throw ArgumentError.value(sourceRev, 'sourceRev', '1..200 chars');
  }
  if (units.length > kSearchMaxUnitsPerOwner) {
    throw ArgumentError.value(units.length, 'units', 'at most 10,000');
  }
  for (final u in units) {
    if (u.body.length > kSearchMaxBodyChars) {
      throw ArgumentError.value(u.body.length, 'body', 'at most 200,000');
    }
    if (u.rects.isNotEmpty && u.rects.length != u.body.length) {
      throw ArgumentError.value(
        u.rects.length,
        'rects',
        'empty or one per UTF-16 code unit of body (${u.body.length})',
      );
    }
    for (final r in u.rects) {
      for (final f in [r.left, r.top, r.right, r.bottom]) {
        if (!f.isFinite ||
            f < -kSearchFractionSlack ||
            f > 1 + kSearchFractionSlack) {
          throw ArgumentError.value(r, 'rects', 'fractions in [0, 1]');
        }
      }
    }
    final a = u.pdfPageAspect;
    if (a != null && !(a.isFinite && a > 0)) {
      throw ArgumentError.value(a, 'pdfPageAspect', 'finite and > 0');
    }
  }
}

/// The asset and PDF page index of a checked pdf owner key.
(AssetId, int) splitPdfOwnerKey(String ownerKey) {
  final hash = ownerKey.indexOf('#');
  return (ownerKey.substring(0, hash), int.parse(ownerKey.substring(hash + 1)));
}
