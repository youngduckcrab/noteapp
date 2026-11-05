// lib/src/common/job_state.dart — value equality (contract 7.4.4): same subtype + same T,
// fields compared with ==. Riverpod 3.4.3 notifies only when previous != next.
// 06-pdf 4.2.
import 'package:flutter/foundation.dart';

import '../errors.dart';
import 'progress.dart';

sealed class PdfJobState<T> {
  const PdfJobState();

  /// The type argument, compared exactly (PdfJobIdle of PdfImportResult is not equal to
  /// PdfJobIdle of PdfExportResult, and a covariant `is` check alone would not see that).
  Type get _type => T;
}

@immutable
final class PdfJobIdle<T> extends PdfJobState<T> {
  const PdfJobIdle();

  /// every PdfJobIdle with the same T is equal
  @override
  bool operator ==(Object other) =>
      other is PdfJobIdle<Object?> && other._type == _type;

  @override
  int get hashCode => Object.hash(PdfJobIdle, _type);

  @override
  String toString() => 'PdfJobIdle';
}

@immutable
final class PdfJobRunning<T> extends PdfJobState<T> {
  const PdfJobRunning(this.progress);
  final PdfProgress progress;

  /// progress ==
  @override
  bool operator ==(Object other) =>
      other is PdfJobRunning<Object?> &&
      other._type == _type &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(PdfJobRunning, _type, progress);

  @override
  String toString() => 'PdfJobRunning($progress)';
}

@immutable
final class PdfJobSucceeded<T> extends PdfJobState<T> {
  const PdfJobSucceeded(this.result);
  final T result;

  /// result == : PdfImportResult is value-equal (4.6); PdfExportResult holds bytes and keeps
  /// identity equality (4.9), so two succeeded exports are equal only for the same object.
  @override
  bool operator ==(Object other) =>
      other is PdfJobSucceeded<Object?> &&
      other._type == _type &&
      other.result == result;

  @override
  int get hashCode => Object.hash(PdfJobSucceeded, _type, result);

  @override
  String toString() => 'PdfJobSucceeded($result)';
}

@immutable
final class PdfJobFailed<T> extends PdfJobState<T> {
  const PdfJobFailed(this.error);
  final PdfIoException error; // code == cancelled for user cancel

  /// error == (code, detail)
  @override
  bool operator ==(Object other) =>
      other is PdfJobFailed<Object?> &&
      other._type == _type &&
      other.error == error;

  @override
  int get hashCode => Object.hash(PdfJobFailed, _type, error);

  @override
  String toString() => 'PdfJobFailed($error)';
}
