// lib/src/model/candidates.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.2). Final since the 2차 foundation step R2-B6.
import 'package:meta/meta.dart';

@immutable
final class TextCandidate {
  const TextCandidate(this.text, {this.score, required this.languageTag});

  final String text;

  /// engine-specific; never compared across engines
  final double? score;
  final String languageTag;

  @override
  bool operator ==(Object other) =>
      other is TextCandidate &&
      other.text == text &&
      other.score == score &&
      other.languageTag == languageTag;

  @override
  int get hashCode => Object.hash(text, score, languageTag);

  @override
  String toString() => 'TextCandidate($text, ${score ?? '-'}, $languageTag)';
}

enum RecognitionModelState { notDownloaded, downloading, ready, unsupported }
