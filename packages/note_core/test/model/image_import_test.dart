// Image import value types (2nd-round contract 7.2.6, m5-7/02-core 4.7). Web-safe.
import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void main() {
  const asset = Asset(
    id: 'a',
    ownerId: kLocalOwnerId,
    type: AssetType.image,
    mimeType: 'image/png',
    size: 10,
    createdAt: 1,
  );

  test('limits', () {
    expect(ImageImportLimits.maxLongSidePx, 2048);
    expect(ImageImportLimits.maxBytes, 8 * 1024 * 1024);
    expect(ImageImportLimits.storedMimeTypes, {'image/jpeg', 'image/png'});
    expect(ImageImportSource.values, hasLength(4));
  });

  test('ImportedImage ==, hashCode', () {
    const a = ImportedImage(asset: asset, pixelWidth: 400, pixelHeight: 300);
    expect(
      a,
      const ImportedImage(asset: asset, pixelWidth: 400, pixelHeight: 300),
    );
    expect(
      a.hashCode,
      const ImportedImage(
        asset: asset,
        pixelWidth: 400,
        pixelHeight: 300,
      ).hashCode,
    );
    expect(
      a,
      isNot(
        const ImportedImage(asset: asset, pixelWidth: 401, pixelHeight: 300),
      ),
    );
  });
}
