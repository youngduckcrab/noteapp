/// Test helpers of pdf_io (06-pdf 4.14): PDF fixture builder and fakes of the pdf_io ports.
///
/// Web-safe; no flutter_test, no dart:io. Import from `test/` only (contract 7.1 rule 2).
/// Other areas (mainly INFRA app shell tests) may use it too. For CORE use the shared fake
/// `createFakeNoteStore()` (contract 7.4.8); FakePdfNoteGateway is a thin port fake for fast
/// unit tests.
///
/// The fixture builder is real (PDF T2). The fakes are signatures only until the PDF task
/// named in each UnimplementedError (T4 gateway, T5 engine, T6 file source, T7 remote
/// fetcher, T12–T16 export fakes).
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import 'src/compose/compose_backend.dart';
import 'src/engine/page_info.dart';
import 'src/engine/pdf_engine.dart';
import 'src/export/compose_plan.dart';
import 'src/export/export_types.dart';
import 'src/export/vectors.dart';
import 'src/files/pdf_file_source.dart';
import 'src/gateway/pdf_note_gateway.dart';
import 'src/output/pdf_output_sink.dart';

Never _todo(String member, String task) =>
    throw UnimplementedError('$member (PDF $task)');

/// Text drawn with the base-14 Helvetica font. When [mapped] is true every distinct
/// UTF-16 code unit gets a single-byte code and a ToUnicode CMap entry, so ANY BMP text
/// (e.g. Korean, incl. NFD jamo) is extractable without embedding a font (verified V12).
@immutable
final class PdfFixtureText {
  const PdfFixtureText(
    this.text, {
    this.x = 72,
    this.y = 72,
    this.size = 18,
    this.mapped = false,
  });
  final String text;

  /// baseline origin in DISPLAYED page pt, y down; converted to
  /// user space with the inverse of D (6.11.3), text rotated with the page
  final double x, y;
  final double size;
  final bool mapped;
}

@immutable
final class PdfFixturePage {
  const PdfFixturePage({
    this.width = 595.2756,
    this.height = 841.8898,
    this.rotate = 0,
    this.mediaBox,
    this.cropBox,
    this.texts = const [],
    this.rawContent,
  });
  final double width, height; // used when mediaBox is null: [0 0 width height]
  final int rotate; // 0, 90, 180, 270
  final List<double>? mediaBox; // [l b r t]
  final List<double>? cropBox;
  final List<PdfFixtureText> texts;
  final String? rawContent; // appended verbatim (e.g. unbalanced 'cm')
}

/// Pure Dart raw PDF 1.4 writer (classic xref). Optional Standard security handler
/// R2 (RC4 40-bit) — PDFium opens it (verified V2).
///
/// Output is deterministic (same pages → same bytes). Object layout: 1 catalog, 2 page tree,
/// 3 shared Helvetica (WinAnsi), then — only when a text is [PdfFixtureText.mapped] — 4 the
/// shared mapped Helvetica and 5 its ToUnicode CMap, then a page and a content stream per
/// page, then the encryption dictionary. Mapped texts share one code table for the whole
/// document: at most 188 distinct UTF-16 code units (printable WinAnsi codes, so each code
/// draws a real Helvetica glyph and has a glyph box).
final class PdfFixtureBuilder {
  PdfFixtureBuilder();

  final List<PdfFixturePage> _pages = [];
  String? _userPassword;
  String _ownerPassword = 'owner';

  PdfFixtureBuilder addPage(PdfFixturePage page) {
    _pages.add(page);
    return this;
  }

  PdfFixtureBuilder addPages(
    int count,
    PdfFixturePage Function(int index) page,
  ) {
    for (var i = 0; i < count; i++) {
      _pages.add(page(i));
    }
    return this;
  }

  /// userPassword '' + ownerPassword = permission-only encryption.
  PdfFixtureBuilder encrypt({
    required String userPassword,
    String ownerPassword = 'owner',
  }) {
    _userPassword = userPassword;
    _ownerPassword = ownerPassword;
    return this;
  }

  /// One shared Helvetica font object for all pages (resource sharing like real PDFs).
  Uint8List build() {
    if (_pages.isEmpty) throw StateError('PdfFixtureBuilder: add a page first');
    final codes = _MappedCodes.of(_pages);
    final hasMapped = codes.isNotEmpty;
    final firstPageObject = hasMapped ? 6 : 4;
    final pageCount = _pages.length;
    final encryptObject = firstPageObject + 2 * pageCount;
    final userPassword = _userPassword;
    final security = userPassword == null
        ? null
        : _FixtureSecurity(userPassword, _ownerPassword, pageCount);

    final objects = <List<int>>[];
    final kids = [
      for (var i = 0; i < pageCount; i++) '${firstPageObject + 2 * i} 0 R',
    ].join(' ');
    objects
      ..add(_ascii('<< /Type /Catalog /Pages 2 0 R >>'))
      ..add(_ascii('<< /Type /Pages /Kids [$kids] /Count $pageCount >>'))
      ..add(
        _ascii(
          '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
          '/Encoding /WinAnsiEncoding >>',
        ),
      );
    if (hasMapped) {
      objects
        ..add(
          _ascii(
            '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
            '/Encoding /WinAnsiEncoding /ToUnicode 5 0 R >>',
          ),
        )
        ..add(_stream(5, _ascii(codes.toUnicodeCMap()), security));
    }
    final fonts = hasMapped ? '/F1 3 0 R /F2 4 0 R' : '/F1 3 0 R';
    for (var i = 0; i < pageCount; i++) {
      final page = _pages[i];
      final pageObject = firstPageObject + 2 * i;
      final box = page.mediaBox ?? [0, 0, page.width, page.height];
      final crop = page.cropBox;
      final dict = StringBuffer(
        '<< /Type /Page /Parent 2 0 R /MediaBox ${_array(box)}',
      );
      if (crop != null) dict.write(' /CropBox ${_array(crop)}');
      if (page.rotate != 0) dict.write(' /Rotate ${_rotation(page.rotate)}');
      dict.write(
        ' /Resources << /Font << $fonts >> >> /Contents ${pageObject + 1} 0 R >>',
      );
      objects
        ..add(_ascii(dict.toString()))
        ..add(
          _stream(
            pageObject + 1,
            _ascii(_content(page, crop ?? box, codes)),
            security,
          ),
        );
    }
    if (security != null) objects.add(_ascii(security.dictionary()));

    final out = BytesBuilder(copy: false)
      ..add(_ascii('%PDF-1.4\n%'))
      ..add(const [0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
    final offsets = <int>[];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(out.length);
      out
        ..add(_ascii('${i + 1} 0 obj\n'))
        ..add(objects[i])
        ..add(_ascii('\nendobj\n'));
    }
    final xref = out.length;
    final trailer = StringBuffer('xref\n0 ${objects.length + 1}\n')
      ..write('0000000000 65535 f \n');
    for (final offset in offsets) {
      trailer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    trailer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R');
    if (security != null) {
      final id = _hex(security.fileId);
      trailer.write(' /Encrypt $encryptObject 0 R /ID [<$id> <$id>]');
    }
    trailer.write(' >>\nstartxref\n$xref\n%%EOF\n');
    out.add(_ascii(trailer.toString()));
    return out.toBytes();
  }

  static int _rotation(int rotate) {
    if (rotate % 90 != 0) {
      throw ArgumentError.value(rotate, 'rotate', 'must be a multiple of 90');
    }
    return (rotate % 360 + 360) % 360;
  }

  /// Text first (each in its own BT/ET), then [PdfFixturePage.rawContent] verbatim.
  static String _content(
    PdfFixturePage page,
    List<double> box,
    _MappedCodes codes,
  ) {
    final d = _displayToUser(box, _rotation(page.rotate) ~/ 90);
    final out = StringBuffer();
    for (final t in page.texts) {
      final ux = d[0] * t.x + d[2] * t.y + d[4];
      final uy = d[1] * t.x + d[3] * t.y + d[5];
      // Glyph x axis = display +x, glyph y axis = display up (0, −1).
      final tm = [d[0], d[1], -d[2], -d[3], ux, uy].map(_num).join(' ');
      final font = t.mapped ? '/F2' : '/F1';
      final shown = t.mapped ? codes.encode(t.text) : _literal(t.text);
      out.write('BT $font ${_num(t.size)} Tf $tm Tm $shown Tj ET\n');
    }
    final raw = page.rawContent;
    if (raw != null) out.write(raw);
    return out.toString();
  }

  /// 6.11.3 D (display pt, y down → user space) for a [l b r t] box and rotation 0..3.
  static List<double> _displayToUser(List<double> box, int rot) {
    if (box.length != 4) {
      throw ArgumentError.value(box, 'box', 'needs [l b r t]');
    }
    final l = box[0], b = box[1], r = box[2], t = box[3];
    return switch (rot) {
      0 => [1, 0, 0, -1, l, t],
      1 => [0, 1, 1, 0, l, b],
      2 => [-1, 0, 0, 1, r, b],
      _ => [0, -1, -1, 0, r, t],
    };
  }

  /// WinAnsi literal string; characters outside Latin-1 need `mapped: true`.
  static String _literal(String text) {
    final out = StringBuffer('(');
    for (final c in text.codeUnits) {
      if (c > 0xFF) {
        throw ArgumentError.value(
          text,
          'text',
          'non-Latin-1 text needs PdfFixtureText(mapped: true)',
        );
      }
      if (c == 0x28 || c == 0x29 || c == 0x5C) {
        out.write('\\${String.fromCharCode(c)}');
      } else if (c < 0x20 || c > 0x7E) {
        out.write('\\${c.toRadixString(8).padLeft(3, '0')}');
      } else {
        out.writeCharCode(c);
      }
    }
    out.write(')');
    return out.toString();
  }

  static String _array(List<double> values) =>
      '[${values.map(_num).join(' ')}]';

  /// Plain decimal (no exponent), at most 4 fraction digits.
  static String _num(double v) {
    if (v == 0) return '0';
    var s = v.toStringAsFixed(4);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s == '-0' ? '0' : s;
  }

  static List<int> _stream(
    int objectNumber,
    List<int> data,
    _FixtureSecurity? security,
  ) {
    final bytes = security == null
        ? data
        : security.encryptObject(objectNumber, data);
    return [
      ..._ascii('<< /Length ${bytes.length} >>\nstream\n'),
      ...bytes,
      ..._ascii('\nendstream'),
    ];
  }
}

List<int> _ascii(String s) => s.codeUnits;

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Shared code table of the mapped Helvetica: UTF-16 code unit → printable WinAnsi code.
final class _MappedCodes {
  _MappedCodes._(this._codeOf);

  static final List<int> _available = [
    for (var c = 0x21; c <= 0x7E; c++) c,
    for (var c = 0xA1; c <= 0xFF; c++)
      if (c != 0xAD) c,
  ];

  static _MappedCodes of(List<PdfFixturePage> pages) {
    final codeOf = <int, int>{};
    for (final page in pages) {
      for (final text in page.texts) {
        if (!text.mapped) continue;
        for (final unit in text.text.codeUnits) {
          if (codeOf.containsKey(unit)) continue;
          if (codeOf.length == _available.length) {
            throw StateError(
              'mapped texts use more than ${_available.length} distinct code units',
            );
          }
          codeOf[unit] = _available[codeOf.length];
        }
      }
    }
    return _MappedCodes._(codeOf);
  }

  final Map<int, int> _codeOf;

  bool get isNotEmpty => _codeOf.isNotEmpty;

  String encode(String text) =>
      '<${_hex([for (final u in text.codeUnits) _codeOf[u]!])}>';

  String toUnicodeCMap() {
    final out = StringBuffer(
      '/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n'
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n'
      '/CMapName /PdfIoFixture-UCS def\n/CMapType 2 def\n'
      '1 begincodespacerange\n<00> <FF>\nendcodespacerange\n',
    );
    final entries = _codeOf.entries.toList();
    for (var start = 0; start < entries.length; start += 100) {
      final chunk = entries.skip(start).take(100).toList();
      out.write('${chunk.length} beginbfchar\n');
      for (final e in chunk) {
        out.write(
          '<${_hex([e.value])}> <${e.key.toRadixString(16).padLeft(4, '0')}>\n',
        );
      }
      out.write('endbfchar\n');
    }
    out.write(
      'endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n',
    );
    return out.toString();
  }
}

/// Standard security handler, V 1 / R 2 (RC4 40-bit): PDF 1.7 algorithms 3.1–3.4.
/// Written with arithmetic instead of bit operators (web-safe numbers, contract 7.4.3).
final class _FixtureSecurity {
  _FixtureSecurity(String userPassword, String ownerPassword, int pageCount)
    : permissions = userPassword.isEmpty ? -44 : -4,
      fileId = md5
          .convert(_ascii('pdf_io fixture $pageCount $userPassword'))
          .bytes {
    final ownerKey = md5.convert(_pad(ownerPassword)).bytes.sublist(0, 5);
    owner = _rc4(ownerKey, _pad(userPassword));
    fileKey = md5
        .convert([
          ..._pad(userPassword),
          ...owner,
          ..._le(permissions + 4294967296, 4),
          ...fileId,
        ])
        .bytes
        .sublist(0, 5);
    user = _rc4(fileKey, _padding);
  }

  /// −4: everything allowed (user password); −44: no modify / annotate (permission-only).
  final int permissions;
  final List<int> fileId;
  late final List<int> owner;
  late final List<int> fileKey;
  late final List<int> user;

  String dictionary() =>
      '<< /Filter /Standard /V 1 /R 2 /O <${_hex(owner)}> /U <${_hex(user)}> '
      '/P $permissions >>';

  List<int> encryptObject(int objectNumber, List<int> data) {
    final key = md5
        .convert([...fileKey, ..._le(objectNumber, 3), 0, 0])
        .bytes
        .sublist(0, 10);
    return _rc4(key, data);
  }

  static const List<int> _padding = [
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, //
    0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ];

  static List<int> _pad(String password) {
    final bytes = [for (final c in password.codeUnits) c % 256];
    final used = bytes.length > 32 ? 32 : bytes.length;
    return [...bytes.take(used), ..._padding.take(32 - used)];
  }

  /// Little-endian bytes of a non-negative [value].
  static List<int> _le(int value, int count) {
    final out = <int>[];
    var v = value;
    for (var i = 0; i < count; i++) {
      out.add(v % 256);
      v = v ~/ 256;
    }
    return out;
  }

  static final Uint8List _xorTable = () {
    final table = Uint8List(256 * 256);
    for (var a = 0; a < 256; a++) {
      for (var b = 0; b < 256; b++) {
        var r = 0, bit = 1, x = a, y = b;
        for (var i = 0; i < 8; i++) {
          if (x % 2 != y % 2) r += bit;
          x = x ~/ 2;
          y = y ~/ 2;
          bit *= 2;
        }
        table[a * 256 + b] = r;
      }
    }
    return table;
  }();

  static List<int> _rc4(List<int> key, List<int> data) {
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) % 256;
      final t = s[i];
      s[i] = s[j];
      s[j] = t;
    }
    final out = Uint8List(data.length);
    var i = 0;
    j = 0;
    for (var n = 0; n < data.length; n++) {
      i = (i + 1) % 256;
      j = (j + s[i]) % 256;
      final t = s[i];
      s[i] = s[j];
      s[j] = t;
      out[n] = _xorTable[data[n] * 256 + s[(s[i] + s[j]) % 256]];
    }
    return out;
  }
}

/// pages/texts given in constructor; solid-color images
final class FakePdfEngine implements PdfEngine {
  FakePdfEngine();

  @override
  bool get isInitialized => _todo('FakePdfEngine.isInitialized', 'T5');

  @override
  Future<void> ensureInitialized() =>
      _todo('FakePdfEngine.ensureInitialized', 'T5');

  @override
  Future<PdfEngineDocument> open(
    Uint8List bytes, {
    required String sourceName,
    String fileName = '',
    PdfPasswordCallback? onPassword,
    int maxPasswordAttempts = 5,
    bool transferOwnership = false,
  }) => _todo('FakePdfEngine.open', 'T5');
}

/// In-memory notes/pages/strokes/assets/thumbnails. arriveBytes(id, bytes) stores the bytes and
/// emits bytesArrived (simulates a finished download). holdWrites() makes putPdf / createNote /
/// insertPages / flush stay pending (no completion, no error — CORE commit retry, contract
/// 7.2.9 v1.2) until releaseWrites(). Retry timing itself is tested with CORE
/// createFakeNoteStore(faults:) (T4, T6, T15).
final class FakePdfNoteGateway implements PdfNoteGateway {
  FakePdfNoteGateway();

  /// Stores [bytes] for [id] and emits it on [bytesArrived].
  void arriveBytes(core.AssetId id, Uint8List bytes) =>
      _todo('FakePdfNoteGateway.arriveBytes', 'T4');

  /// putPdf / createNote / insertPages / flush stay pending until [releaseWrites].
  void holdWrites() => _todo('FakePdfNoteGateway.holdWrites', 'T4');

  /// Completes the writes held since [holdWrites].
  void releaseWrites() => _todo('FakePdfNoteGateway.releaseWrites', 'T4');

  @override
  Future<core.Asset> putPdf(Uint8List bytes, {required String fileName}) =>
      _todo('FakePdfNoteGateway.putPdf', 'T4');

  @override
  Future<Uint8List?> readAssetBytes(core.AssetId assetId) =>
      _todo('FakePdfNoteGateway.readAssetBytes', 'T4');

  @override
  Stream<core.AssetId> get bytesArrived =>
      _todo('FakePdfNoteGateway.bytesArrived', 'T4');

  @override
  Future<core.Note> createNote({
    core.FolderId? folderId,
    required String title,
    required List<core.PageDraft> pages,
  }) => _todo('FakePdfNoteGateway.createNote', 'T4');

  @override
  Future<List<core.PageId>> insertPages(
    core.NoteId noteId,
    List<core.PageDraft> pages,
    core.PagePosition position,
  ) => _todo('FakePdfNoteGateway.insertPages', 'T4');

  @override
  Future<void> flush() => _todo('FakePdfNoteGateway.flush', 'T4');

  @override
  Future<core.Note?> getNote(core.NoteId noteId) =>
      _todo('FakePdfNoteGateway.getNote', 'T4');

  @override
  Future<List<core.Page>> pagesOf(core.NoteId noteId) =>
      _todo('FakePdfNoteGateway.pagesOf', 'T4');

  @override
  Future<core.PageContent> loadPage(core.PageId pageId) =>
      _todo('FakePdfNoteGateway.loadPage', 'T4');

  @override
  Future<void> writeThumbnail(core.PageThumbnail thumbnail) =>
      _todo('FakePdfNoteGateway.writeThumbnail', 'T4');
}

/// returns queued PickedPdfFile / null
final class FakePdfFileSource implements PdfFileSource {
  FakePdfFileSource();

  @override
  bool get isSupported => _todo('FakePdfFileSource.isSupported', 'T6');

  @override
  Future<PickedPdfFile?> pickPdf() => _todo('FakePdfFileSource.pickPdf', 'T6');
}

/// records deliveries (result lists)
final class FakePdfOutputSink implements PdfOutputSink {
  FakePdfOutputSink();

  @override
  Set<PdfOutputAction> availableActions(List<PdfExportResult> results) =>
      _todo('FakePdfOutputSink.availableActions', 'T16');

  @override
  Future<PdfOutputOutcome> deliver(
    List<PdfExportResult> results,
    PdfOutputAction action,
  ) => _todo('FakePdfOutputSink.deliver', 'T16');
}

/// records plan/ops, returns '%PDF-fake'
final class RecordingComposeBackend implements PdfComposeBackend {
  RecordingComposeBackend();

  @override
  bool get isSupported => _todo('RecordingComposeBackend.isSupported', 'T15');

  @override
  Future<PdfComposeJob> begin(PdfComposePlan plan) =>
      _todo('RecordingComposeBackend.begin', 'T15');

  @override
  Future<void> dispose() => _todo('RecordingComposeBackend.dispose', 'T15');
}

/// each stroke → filled rect of its bounds
final class BoxInkVectorizer implements PdfInkVectorizer {
  const BoxInkVectorizer();

  @override
  PdfPageVectors vectorize(
    core.Page page,
    List<core.Stroke> strokes, {
    required bool includeInk,
    required bool includeTemplate,
  }) => _todo('BoxInkVectorizer.vectorize', 'T15');
}

/// Scripted core.RemoteAssetFetcher (P-2 tests, also usable by INFRA before M4).
final class FakeRemoteAssetFetcher implements core.RemoteAssetFetcher {
  FakeRemoteAssetFetcher();

  List<core.AssetId> get ensureLocalCalls =>
      _todo('FakeRemoteAssetFetcher.ensureLocalCalls', 'T7');

  /// Pushes a progress value to watch(id) listeners (broadcast; replays the latest on listen).
  void emit(core.AssetId id, core.RemoteAssetProgress progress) =>
      _todo('FakeRemoteAssetFetcher.emit', 'T7');

  /// Completes the pending ensureLocal(id) future with [local].
  void completeEnsureLocal(core.AssetId id, bool local) =>
      _todo('FakeRemoteAssetFetcher.completeEnsureLocal', 'T7');

  @override
  Future<bool> ensureLocal(core.AssetId id) =>
      _todo('FakeRemoteAssetFetcher.ensureLocal', 'T7');

  @override
  Stream<core.RemoteAssetProgress> watch(core.AssetId id) =>
      _todo('FakeRemoteAssetFetcher.watch', 'T7');
}
