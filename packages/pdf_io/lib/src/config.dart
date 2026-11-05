// lib/src/config.dart — 06-pdf 4.1 (contract 00-overview 7.2.19).
import 'package:flutter/foundation.dart';

@immutable
final class PdfImportLimits {
  const PdfImportLimits({
    this.maxBytes = 300 * 1024 * 1024, // hard limit (6.3)
    this.warnBytes = 100 * 1024 * 1024, // confirm dialog above this
    this.maxPages = 2000, // = CORE createNote limit (C-3)
    this.maxPasswordAttempts = 5,
  });
  final int maxBytes;
  final int warnBytes;
  final int maxPages;
  final int maxPasswordAttempts;

  @override
  bool operator ==(Object other) =>
      other is PdfImportLimits &&
      other.maxBytes == maxBytes &&
      other.warnBytes == warnBytes &&
      other.maxPages == maxPages &&
      other.maxPasswordAttempts == maxPasswordAttempts;

  @override
  int get hashCode =>
      Object.hash(maxBytes, warnBytes, maxPages, maxPasswordAttempts);

  @override
  String toString() =>
      'PdfImportLimits(maxBytes: $maxBytes, warnBytes: $warnBytes, '
      'maxPages: $maxPages, maxPasswordAttempts: $maxPasswordAttempts)';
}

/// Byte budgets of the render cache by kind (6.7.4). Web values = contract 7.4.10.
@immutable
final class PdfRenderBudget {
  const PdfRenderBudget({
    required this.previewBytes,
    required this.tileBytes,
    required this.thumbnailBytes,
  });
  const PdfRenderBudget.web()
    : previewBytes = 32 * 1024 * 1024,
      tileBytes = 64 * 1024 * 1024,
      thumbnailBytes = 16 * 1024 * 1024;
  const PdfRenderBudget.native()
    : previewBytes = 64 * 1024 * 1024,
      tileBytes = 160 * 1024 * 1024,
      thumbnailBytes = 32 * 1024 * 1024;
  final int previewBytes;
  final int tileBytes;
  final int thumbnailBytes;

  /// web: 112 MiB
  int get totalBytes => previewBytes + tileBytes + thumbnailBytes;

  @override
  bool operator ==(Object other) =>
      other is PdfRenderBudget &&
      other.previewBytes == previewBytes &&
      other.tileBytes == tileBytes &&
      other.thumbnailBytes == thumbnailBytes;

  @override
  int get hashCode => Object.hash(previewBytes, tileBytes, thumbnailBytes);

  @override
  String toString() =>
      'PdfRenderBudget(previewBytes: $previewBytes, tileBytes: $tileBytes, '
      'thumbnailBytes: $thumbnailBytes)';
}

/// User-password PDFs on import (6.4). Default pending the user's answer (00-review U1).
enum PdfUserPasswordPolicy {
  /// store a copy without the security handler (default)
  storeDecryptedCopy,

  /// reject with PdfErrorCode.userPasswordRefused
  refuse,
}

@immutable
final class PdfIoConfig {
  const PdfIoConfig({
    this.pdfiumWasmModulesUrl, // null → pdfrx default 'assets/packages/pdfrx/assets/' (resolved against document.baseURI)
    this.composeExtensionUrl =
        'assets/packages/pdf_io/web/pdf_io_compose_ext.js',
    this.warmUpOnStart =
        true, // start engine init in the background (not awaited)
    this.limits = const PdfImportLimits(),
    this.renderBudget, // null → web()/native() by platform
    this.generateCoverThumbnail = true,
    this.userPasswordPolicy = PdfUserPasswordPolicy.storeDecryptedCopy,
  });
  final String? pdfiumWasmModulesUrl;
  final String composeExtensionUrl;
  final bool warmUpOnStart;
  final PdfImportLimits limits;
  final PdfRenderBudget? renderBudget;
  final bool generateCoverThumbnail;
  final PdfUserPasswordPolicy userPasswordPolicy;

  /// [renderBudget], or PdfRenderBudget.web() on the web and
  /// PdfRenderBudget.native() elsewhere.
  PdfRenderBudget get effectiveRenderBudget =>
      renderBudget ??
      (kIsWeb ? const PdfRenderBudget.web() : const PdfRenderBudget.native());

  /// Value equality over every field (pdfIoConfigProvider value; initializePdfIo's
  /// "second call with a different config" check uses it).
  @override
  bool operator ==(Object other) =>
      other is PdfIoConfig &&
      other.pdfiumWasmModulesUrl == pdfiumWasmModulesUrl &&
      other.composeExtensionUrl == composeExtensionUrl &&
      other.warmUpOnStart == warmUpOnStart &&
      other.limits == limits &&
      other.renderBudget == renderBudget &&
      other.generateCoverThumbnail == generateCoverThumbnail &&
      other.userPasswordPolicy == userPasswordPolicy;

  @override
  int get hashCode => Object.hash(
    pdfiumWasmModulesUrl,
    composeExtensionUrl,
    warmUpOnStart,
    limits,
    renderBudget,
    generateCoverThumbnail,
    userPasswordPolicy,
  );

  @override
  String toString() =>
      'PdfIoConfig(pdfiumWasmModulesUrl: $pdfiumWasmModulesUrl, '
      'composeExtensionUrl: $composeExtensionUrl, '
      'warmUpOnStart: $warmUpOnStart, limits: $limits, '
      'renderBudget: $renderBudget, '
      'generateCoverThumbnail: $generateCoverThumbnail, '
      'userPasswordPolicy: ${userPasswordPolicy.name})';
}
