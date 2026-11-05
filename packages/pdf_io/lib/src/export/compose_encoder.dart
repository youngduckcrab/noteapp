// lib/src/export/compose_encoder.dart — 06-pdf 4.9, 6.11.5.
//
// Foundation step B4 (T0): signature only; the encoder comes with PDF T12.
import 'compose_plan.dart';
import 'vectors.dart';

abstract final class PdfComposeEncoder {
  /// underlay then ink; every item becomes one PDF path object (6.11.5).
  static PdfComposePageOps encode({
    required int outputIndex,
    required PdfPageVectors vectors,
  }) => throw UnimplementedError('PdfComposeEncoder.encode (PDF T12)');
}
