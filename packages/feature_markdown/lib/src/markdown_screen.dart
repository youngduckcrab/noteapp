// The MD 문서 screen (08-markdown 8, C217M-14; B-6 … B-12). One button toggles 보기
// (rendered) ↔ 편집 (source); on a wide landscape tablet 나란히 shows both. All state of
// the open document lives in MarkdownController (screen/markdown_controller.dart).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:ui_kit/ui_kit.dart';

import 'edit/line_endings.dart';
import 'edit/md_editor.dart';
import 'markdown_keys.dart';
import 'parse/md_document.dart';
import 'parse/md_model.dart';
import 'render/md_link.dart';
import 'render/md_view.dart';
import 'screen/banners.dart';
import 'screen/markdown_controller.dart';
import 'slots_impl.dart';
import 'strings_ko.dart';

/// 나란히 (side-by-side) chosen on this device (08-markdown 13).
final SettingKey<bool> kMarkdownSplitViewSetting = SettingKey.boolean(
  'markdown.splitView',
  false,
  scope: SettingScope.device,
);

/// Text that could not be saved when the screen was left or the app went to the
/// background, per document: `{<noteId>: {text, base, at}}` — `base` is the textVersion
/// (Hlc string, or null) the text was written on, so a restore saves against it and the
/// store keeps a newer text as a conflict copy (CORE L1). An entry is dropped once a later
/// save of that document succeeds, or by [버리기] / [복원].
final SettingKey<Map<String, Object?>> kMarkdownUnsavedSetting =
    SettingKey.jsonMap('markdown.unsaved', scope: SettingScope.device);

/// Documents kept in [kMarkdownUnsavedSetting] at most (the oldest go).
const int kMaxUnsavedDocs = 8;

/// Body width (and landscape) from which 나란히 is offered.
const double kSplitMinWidth = 1100;

/// Below this body width the top bar is compact (icons only, undo / redo in the
/// symbol row).
const double kNarrowTopBar = 600;

/// One MD 문서, full screen: 보기 (rendered) ↔ 편집 (source) with one button.
///
/// Wrapped by the app in the editor style (`EditorStyleScope`) like the ink editor.
class MarkdownScreen extends ConsumerStatefulWidget {
  const MarkdownScreen({
    super.key,
    required this.noteId,
    this.initialQuery,
    this.initialEdit = false,
    required this.onClose,
    this.onOpenAsNote,
    this.onOpenMarkdown,
  });

  /// The MD 문서 (a note with `isMarkdown`).
  final NoteId noteId;

  /// Library search text: after the first frame the view scrolls to the first match and
  /// highlights it (08-markdown 8.8). null = top of the document.
  final String? initialQuery;

  /// Open in 편집 (a document just made with '새 MD 문서'); otherwise 보기.
  final bool initialEdit;

  /// Back: called after the screen has saved and flushed (or the user chose to leave
  /// after a failed save — the text is never dropped silently).
  final VoidCallback onClose;

  /// When [noteId] is a handwriting note: [노트로 열기]. null hides the button.
  final VoidCallback? onOpenAsNote;

  /// Opens another MD 문서 (the conflict copy's [사본 열기]). null hides the button.
  final ValueChanged<NoteId>? onOpenMarkdown;

  @override
  ConsumerState<MarkdownScreen> createState() => _MarkdownScreenState();
}

enum _Mode { view, edit, split }

class _MarkdownScreenState extends ConsumerState<MarkdownScreen> {
  late final MarkdownController _c;

  /// Read once: also used while (and after) the screen is disposed.
  late final SettingsRepository _settings;
  late final AppLifecycleListener _life;
  final MdViewController _view = MdViewController();
  final MdViewController _preview = MdViewController();
  final FocusNode _editorFocus = FocusNode(debugLabel: 'md editor');
  final GlobalKey _editorKey = GlobalKey(debugLabel: 'md editor pane');

  _Mode _mode = _Mode.view;
  bool _editorMounted = false;
  bool _splitSetting = false;
  bool _wide = false;

  MdDocument _parsed = MdDocument.empty;
  String? _parsing;

  /// The controller's revision the shown parse was made at (an outside change bumps it).
  int _parsedRevision = 0;
  Timer? _parseTimer;

  bool _landed = false;
  int? _highlight;
  Timer? _highlightTimer;

  Timer? _receivingTimer;
  bool _receivingLong = false;

  Map<String, Object?>? _unsaved;

  /// This screen wrote an entry for its document into kMarkdownUnsavedSetting.
  bool _keptUnsaved = false;
  bool _leaving = false;
  bool _wasLoaded = false;

  @override
  void initState() {
    super.initState();
    // Read once: the controller outlives this state by its last flush (dispose).
    final store = ref.read(noteStoreProvider);
    _settings = ref.read(settingsRepositoryProvider);
    _c = MarkdownController(
      noteId: widget.noteId,
      repository: ref.read(markdownRepositoryProvider),
      flushStore: store.flush,
      onSaved: _onSaved,
    )..addListener(_onController);
    if (widget.initialEdit) {
      _mode = _Mode.edit;
      _editorMounted = true;
    }
    _life = AppLifecycleListener(
      onHide: _onBackground,
      onPause: _onBackground,
      onDetach: _onBackground,
    );
    unawaited(_readSettings());
  }

  Future<void> _readSettings() async {
    final settings = _settings;
    try {
      final split = await settings.get(kMarkdownSplitViewSetting);
      final unsaved = await settings.get(kMarkdownUnsavedSetting);
      if (!mounted) return;
      final mine = unsaved[widget.noteId];
      setState(() {
        _splitSetting = split;
        if (mine is Map && mine['text'] is String) {
          _unsaved = Map<String, Object?>.of(mine.cast<String, Object?>());
        }
      });
      _checkUnsaved();
    } on Object catch (e) {
      debugPrint('feature_markdown: settings: $e');
    }
  }

  @override
  void dispose() {
    _life.dispose();
    _parseTimer?.cancel();
    _highlightTimer?.cancel();
    _receivingTimer?.cancel();
    _c.removeListener(_onController);
    // Save what is left, then let the controller go. When that save fails too (the route
    // was replaced or popped some other way than [←] / back), the text is kept on this
    // device like on app pause — it is never dropped silently.
    final c = _c;
    final settings = _settings;
    final noteId = widget.noteId;
    unawaited(() async {
      try {
        final ok = await c.flush(store: true);
        if (!ok && c.dirty) {
          await _keepUnsaved(settings, noteId, c.encoded, c.base);
        }
      } finally {
        c.dispose();
      }
    }());
    _view.dispose();
    _preview.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  // --- controller events --------------------------------------------------------

  void _onController() {
    if (!mounted) return;
    final doc = _c.doc;
    if (_c.loaded && !_wasLoaded) {
      _wasLoaded = true;
      if (_mode != _Mode.view && !_c.canEdit) {
        _mode = _Mode.view;
      }
      _ensureParsed(immediate: true);
      _checkUnsaved();
    } else if (_mode != _Mode.edit) {
      // 보기 draws the buffer at once; 나란히 previews it after 200 ms. 편집 never parses.
      _ensureParsed(immediate: _mode == _Mode.view);
    }
    if (_mode != _Mode.view && !_c.canEdit && doc != null) {
      // The document became read-only (trashed elsewhere, …): back to 보기.
      _mode = _Mode.view;
      _editorFocus.unfocus();
      _ensureParsed(immediate: true);
    }
    final receiving = doc?.readOnlyReason == MarkdownReadOnlyReason.bodyMissing;
    if (receiving && _receivingTimer == null) {
      _receivingTimer = Timer(const Duration(minutes: 2), () {
        if (mounted) setState(() => _receivingLong = true);
      });
    } else if (!receiving && _receivingTimer != null) {
      _receivingTimer!.cancel();
      _receivingTimer = null;
      _receivingLong = false;
    }
    setState(() {});
  }

  void _checkUnsaved() {
    final u = _unsaved;
    final d = _c.doc;
    if (u == null || d == null) return;
    if (u['text'] == d.text) {
      _discardUnsaved();
    }
  }

  /// A save of this document succeeded: text this screen kept for later is out of date.
  void _onSaved() {
    if (!_keptUnsaved) return;
    _keptUnsaved = false;
    unawaited(_clearUnsavedSetting());
  }

  // --- parsing ------------------------------------------------------------------

  void _ensureParsed({bool immediate = false}) {
    final src = _c.text.text;
    if (src == _parsed.source && _parsed.blocks.isNotEmpty) return;
    if (src == _parsing) return;
    if (src.isEmpty && _parsed.source.isEmpty) return;
    _parseTimer?.cancel();
    if (immediate) {
      unawaited(_parse(src));
    } else {
      _parseTimer = Timer(
        const Duration(milliseconds: 200),
        () => unawaited(_parse(_c.text.text)),
      );
    }
  }

  Future<void> _parse(String src) async {
    _parsing = src;
    final MdDocument doc;
    if (src.length <= kParseOffThreadChars) {
      doc = parseMarkdown(src);
    } else {
      // A large document: its first screenful now, the whole one from the isolate.
      if (_parsed.blocks.isEmpty) {
        final head = parseMarkdownHead(src);
        if (head != null && mounted) {
          setState(() => _parsed = head);
          // Paint it before the isolate starts (spawning and the result copy cost
          // main-isolate time too).
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
        }
      }
      doc = await parseMarkdownAsync(src);
    }
    if (!mounted) return;
    if (_parsing == src) _parsing = null;
    // Another device's text (or a restore) replaced the buffer while 보기 shows it: keep
    // the block at the top of the view at the top (08-markdown 8.7 ③), found by its key.
    String? topKey;
    ({int block, double dy})? anchor;
    if (_mode == _Mode.view && _c.revision != _parsedRevision) {
      anchor = _view.topAnchor();
      if (anchor != null && anchor.block < _parsed.blocks.length) {
        topKey = _parsed.blocks[anchor.block].key;
      }
    }
    _parsedRevision = _c.revision;
    setState(() => _parsed = doc);
    if (topKey != null) {
      final now = doc.blocks.indexWhere((b) => b.key == topKey);
      final dy = anchor!.dy;
      if (now >= 0 && now != anchor.block) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_view.restoreAnchor(now, dy));
        });
      }
    }
    _maybeLand();
    if (_c.text.text != src && _mode != _Mode.edit) _ensureParsed();
  }

  // --- search landing -----------------------------------------------------------

  void _maybeLand() {
    if (_landed || !_c.loaded || _parsed.source != _c.text.text) return;
    _landed = true;
    final q = SearchText.normalize(widget.initialQuery ?? '');
    if (q.isEmpty || _mode != _Mode.view) return;
    final mapping = SearchText.normalizeMapped(_c.text.text);
    final at = mapping.text.indexOf(q);
    if (at < 0) return;
    final block = _parsed.blockAt(mapping.sourceStart[at]);
    if (block < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _highlight = block);
      await _view.revealBlock(block);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _highlight = null);
      });
    });
  }

  // --- modes --------------------------------------------------------------------

  Future<void> _toView() async {
    if (_mode == _Mode.view) return;
    // The block with the cursor comes to the top of the view.
    final sel = _c.text.selection;
    _editorFocus.unfocus();
    setState(() => _mode = _Mode.view);
    _ensureParsed(immediate: true);
    unawaited(_c.flush(store: true));
    if (sel.isValid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _parsed.source != _c.text.text) return;
        final b = _parsed.blockAt(sel.extentOffset);
        if (b > 0) unawaited(_view.revealBlock(b));
      });
    }
  }

  void _toEdit() {
    if (!_c.canEdit) return;
    // The block at the top of the view gets the cursor (the field scrolls to it).
    final top = _mode == _Mode.view ? _view.firstVisibleBlock() : null;
    if (top != null && top > 0 && top < _parsed.blocks.length) {
      final at = _parsed.blocks[top].start.clamp(0, _c.text.text.length);
      _c.text.selection = TextSelection.collapsed(offset: at);
    }
    setState(() {
      _editorMounted = true;
      _mode = _wide && _splitSetting ? _Mode.split : _Mode.edit;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _mode != _Mode.view) _editorFocus.requestFocus();
    });
  }

  void _setSplit(bool on) {
    setState(() {
      _splitSetting = on;
      _mode = on ? _Mode.split : _Mode.edit;
      _editorMounted = true;
    });
    if (on) _ensureParsed(immediate: true);
    unawaited(
      _settings.set(kMarkdownSplitViewSetting, on).catchError((Object _) {}),
    );
  }

  // --- leaving ------------------------------------------------------------------

  Future<void> _onBackground() async {
    final settings = _settings;
    final ok = await _c.flush(store: true);
    if (ok || !_c.dirty) return;
    // Cannot ask now: keep the text on this device for the next opening.
    if (await _keepUnsaved(settings, widget.noteId, _c.encoded, _c.base)) {
      _keptUnsaved = true;
      // A save that succeeded while the setting was being written.
      if (!_c.dirty && mounted) _onSaved();
    }
  }

  /// Writes [text] (written on [base]) into kMarkdownUnsavedSetting for [noteId].
  static Future<bool> _keepUnsaved(
    SettingsRepository settings,
    NoteId noteId,
    String text,
    Hlc? base,
  ) async {
    try {
      final all = Map<String, Object?>.of(
        await settings.get(kMarkdownUnsavedSetting),
      )..remove(noteId);
      // Old single-slot shape ({noteId, text, at}) and the oldest entries go.
      all.removeWhere((_, v) => v is! Map);
      while (all.length >= kMaxUnsavedDocs) {
        String? oldest;
        var at = 1 << 62;
        for (final e in all.entries) {
          final t = (e.value! as Map)['at'];
          final ms = t is int ? t : 0;
          if (ms < at) {
            at = ms;
            oldest = e.key;
          }
        }
        all.remove(oldest);
      }
      all[noteId] = {
        'text': text,
        'base': base?.toString(),
        'at': DateTime.now().millisecondsSinceEpoch,
      };
      await settings.set(kMarkdownUnsavedSetting, all);
      return true;
    } on Object catch (e) {
      debugPrint('feature_markdown: could not keep unsaved text: $e');
      return false;
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      _editorFocus.unfocus();
      final ok = await _c.flush(store: true);
      if (!mounted) return;
      if (ok || !_c.dirty) {
        widget.onClose();
        return;
      }
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          key: MarkdownKeys.leaveDialog,
          title: const Text(MdStrings.leaveTitle),
          content: const Text(MdStrings.leaveBody),
          actions: [
            TextButton(
              key: MarkdownKeys.leaveDiscard,
              onPressed: () => Navigator.of(context).pop('discard'),
              child: const Text(MdStrings.leaveDiscard),
            ),
            TextButton(
              key: MarkdownKeys.leaveCopy,
              onPressed: () => Navigator.of(context).pop('copy'),
              child: const Text(MdStrings.leaveCopy),
            ),
            FilledButton(
              key: MarkdownKeys.leaveStay,
              onPressed: () => Navigator.of(context).pop('stay'),
              child: const Text(MdStrings.leaveStay),
            ),
          ],
        ),
      );
      if (!mounted) return;
      switch (choice) {
        case 'copy':
          // The copy is extra: the text is still saved when the screen goes (or kept
          // on this device when that fails too).
          await Clipboard.setData(ClipboardData(text: _c.encoded));
          widget.onClose();
        case 'discard':
          _c.discard();
          widget.onClose();
        default:
          break;
      }
    } finally {
      _leaving = false;
    }
  }

  void _onBack() {
    if (_mode != _Mode.view) {
      unawaited(_toView());
    } else {
      unawaited(_leave());
    }
  }

  // --- view callbacks -----------------------------------------------------------

  void _onLink(MdLink link) {
    final href = link.href.trim();
    if (href.startsWith('#')) {
      final slug = Uri.decodeComponent(href.substring(1)).toLowerCase();
      final block = _parsed.slugs[slug];
      if (block == null) {
        _say(MdStrings.linkNoAnchor);
      } else {
        unawaited(_viewFor().revealBlock(block));
      }
      return;
    }
    unawaited(
      showLinkSheet(
        context,
        href: href,
        openLink: ref.read(markdownOpenLinkProvider),
      ),
    );
  }

  MdViewController _viewFor() => _mode == _Mode.split ? _preview : _view;

  void _onFootnote(String label) =>
      unawaited(_viewFor().revealBlock(_parsed.blocks.length));

  bool _canToggle(int i) =>
      _c.canEdit &&
      _parsed.source == _c.text.text &&
      i < _parsed.taskOffsets.length &&
      _parsed.taskOffsets[i] != null;

  Future<void> _toggleTask(int i) async {
    if (!_canToggle(i)) return;
    final offset = _parsed.taskOffsets[i]!;
    final before = _c.text.text;
    final changed = _c.toggleTaskAt(offset);
    // The text right after the toggle: [되돌리기] flips the box back only while the
    // buffer is still exactly that (typing in 나란히, another device's text or a second
    // toggle would move the offsets — then the snack bar's undo does nothing).
    final after = _c.text.text;
    _ensureParsed(immediate: true);
    if (!await changed && _c.text.text == before) return;
    if (!mounted || after == before) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: const Text(MdStrings.taskChanged),
        action: SnackBarAction(
          key: MarkdownKeys.taskUndo,
          label: MdStrings.undo,
          onPressed: () {
            if (_c.text.text != after) return;
            unawaited(_c.toggleTaskAt(offset));
            _ensureParsed(immediate: true);
          },
        ),
      ),
    );
  }

  /// [사본 열기]: saves first (like back), then lets the app open the copy.
  Future<void> _openCopy(NoteId copy) async {
    _c.dismissConflictCopy();
    await _c.flush(store: true);
    if (mounted) widget.onOpenMarkdown?.call(copy);
  }

  void _say(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // --- menu ---------------------------------------------------------------------

  Future<void> _rename() async {
    final note = _c.doc?.note;
    if (note == null) return;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: note.title),
    );
    final t = title?.trim() ?? '';
    if (t.isEmpty || t == note.title) return;
    try {
      await ref.read(libraryRepositoryProvider).renameNote(widget.noteId, t);
    } on Object catch (e) {
      debugPrint('feature_markdown: rename failed: $e');
      if (mounted) _say(MdStrings.renameFailed);
    }
  }

  Future<void> _export() async {
    final action = ref.read(markdownExportActionProvider);
    final note = _c.doc?.note;
    if (action == null || note == null) return;
    await _c.flush();
    if (!mounted) return;
    try {
      await action(context, title: note.title, text: _c.encoded);
    } on Object catch (e) {
      debugPrint('feature_markdown: export failed: $e');
      if (mounted) _say(MdStrings.exportFailed);
    }
  }

  Future<void> _info() async {
    final d = _c.doc;
    if (d == null) return;
    final raw = _c.encoded;
    final at = DateTime.fromMillisecondsSinceEpoch(d.note.updatedAt);
    String two(int v) => v.toString().padLeft(2, '0');
    final when =
        '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(MdStrings.infoTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(
              MdStrings.infoChars,
              MdStrings.chars(_c.text.text.characters.length),
            ),
            _infoRow(
              MdStrings.infoBytes,
              MdStrings.bytes(MarkdownLimits.utf8BytesOf(raw)),
            ),
            _infoRow(MdStrings.infoModified, when),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(MdStrings.close),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );

  // --- unsaved text -------------------------------------------------------------

  Future<void> _restoreUnsaved() async {
    final raw = _unsaved?['text'];
    if (raw is! String) return;
    final base = Hlc.tryParse(_unsaved?['base'] as String?);
    _c.codec = LineEndingCodec.of(raw);
    final text = _c.codec.decode(raw);
    setState(() => _unsaved = null);
    await _c.restoreText(text, base: base);
    _ensureParsed(immediate: true);
    await _clearUnsavedSetting();
  }

  void _discardUnsaved() {
    setState(() => _unsaved = null);
    unawaited(_clearUnsavedSetting());
  }

  /// Drops this document's entry of kMarkdownUnsavedSetting (others stay).
  Future<void> _clearUnsavedSetting() async {
    try {
      final settings = _settings;
      final all = Map<String, Object?>.of(
        await settings.get(kMarkdownUnsavedSetting),
      );
      if (all.remove(widget.noteId) == null) return;
      if (all.isEmpty) {
        await settings.reset(kMarkdownUnsavedSetting);
      } else {
        await settings.set(kMarkdownUnsavedSetting, all);
      }
    } on Object catch (_) {}
  }

  // --- build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = StyleTokens.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        key: MarkdownKeys.screen,
        backgroundColor: t.toolbar,
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = MediaQuery.sizeOf(context);
              _wide =
                  constraints.maxWidth >= kSplitMinWidth &&
                  size.width > size.height;
              final narrow = constraints.maxWidth < kNarrowTopBar;
              final mode = _mode == _Mode.split && !_wide ? _Mode.edit : _mode;
              return Column(
                children: [
                  _topBar(context, mode, narrow),
                  ..._banners(),
                  Expanded(child: _body(context, mode, narrow)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, _Mode mode, bool narrow) {
    final t = StyleTokens.of(context);
    final theme = Theme.of(context);
    final doc = _c.doc;
    final title = doc?.note.title ?? '';
    final editing = mode != _Mode.view;
    final canEdit = _c.canEdit;
    Widget modeButton() {
      final (AppIconKind icon, String label, String tip) = switch (mode) {
        _Mode.view => (
          AppIconKind.editSource,
          MdStrings.edit,
          MdStrings.toEdit,
        ),
        _Mode.edit => (
          AppIconKind.viewRendered,
          MdStrings.view,
          MdStrings.toView,
        ),
        _Mode.split => (
          AppIconKind.splitView,
          MdStrings.splitOff,
          MdStrings.splitOff,
        ),
      };
      final VoidCallback? onPressed = switch (mode) {
        _Mode.view => canEdit ? _toEdit : null,
        _Mode.edit => () => unawaited(_toView()),
        _Mode.split => () => _setSplit(false),
      };
      if (narrow) {
        return IconButton(
          key: MarkdownKeys.mode,
          tooltip: tip,
          onPressed: onPressed,
          icon: AppIcon(icon),
        );
      }
      return Tooltip(
        message: tip,
        child: TextButton.icon(
          key: MarkdownKeys.mode,
          onPressed: onPressed,
          icon: AppIcon(icon, size: 20),
          label: Text(label),
        ),
      );
    }

    return Material(
      color: t.toolbar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.hairline)),
        ),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 4),
              IconButton(
                key: MarkdownKeys.back,
                tooltip: MdStrings.back,
                // Same order as system back (08-markdown 8.4): 편집 / 나란히 → 보기 first.
                onPressed: _onBack,
                icon: const AppIcon(AppIconKind.back),
              ),
              Expanded(
                child: Semantics(
                  button: doc != null,
                  hint: MdStrings.renameTooltip,
                  child: InkWell(
                    key: MarkdownKeys.title,
                    borderRadius: BorderRadius.circular(t.radiusSmall),
                    onTap: doc == null || doc.note.isDeleted ? null : _rename,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (doc != null) ...[
                if (editing && !narrow) ..._undoButtons(t),
                if (editing || _c.state != MdSaveState.saved)
                  _saveState(context, narrow),
                if (_wide && mode == _Mode.edit)
                  IconButton(
                    key: MarkdownKeys.split,
                    tooltip: MdStrings.splitTooltip,
                    onPressed: () => _setSplit(true),
                    icon: const AppIcon(AppIconKind.splitView),
                  ),
                modeButton(),
                _menu(context),
              ],
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _undoButtons(StyleTokens t) => [
    ValueListenableBuilder<UndoHistoryValue>(
      valueListenable: _c.undo,
      builder: (context, v, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: MarkdownKeys.undo,
            tooltip: MdStrings.undo,
            onPressed: v.canUndo ? _c.undoStep : null,
            icon: const AppIcon(AppIconKind.undo),
          ),
          IconButton(
            key: MarkdownKeys.redo,
            tooltip: MdStrings.redo,
            onPressed: v.canRedo ? _c.redoStep : null,
            icon: const AppIcon(AppIconKind.redo),
          ),
        ],
      ),
    ),
  ];

  Widget _saveState(BuildContext context, bool narrow) {
    final t = StyleTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (String label, AppIconKind icon, Color color) = switch (_c.state) {
      MdSaveState.saved => (
        MdStrings.saved,
        AppIconKind.check,
        t.textSecondary,
      ),
      MdSaveState.pending || MdSaveState.saving => (
        MdStrings.saving,
        AppIconKind.history,
        t.textSecondary,
      ),
      MdSaveState.failed => (
        MdStrings.saveFailed,
        AppIconKind.error,
        scheme.error,
      ),
    };
    return Semantics(
      liveRegion: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Padding(
          key: MarkdownKeys.saveState,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: narrow
              ? AppIcon(icon, size: 20, color: color)
              : ExcludeSemantics(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: color),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context) {
    final canExport = ref.watch(markdownExportActionProvider) != null;
    return PopupMenuButton<String>(
      key: MarkdownKeys.more,
      tooltip: MdStrings.more,
      icon: const AppIcon(AppIconKind.more),
      onSelected: (v) {
        switch (v) {
          case 'export':
            unawaited(_export());
          case 'rename':
            unawaited(_rename());
          case 'info':
            unawaited(_info());
        }
      },
      itemBuilder: (context) => [
        if (canExport)
          const PopupMenuItem(
            key: MarkdownKeys.menuExport,
            value: 'export',
            child: _MenuRow(AppIconKind.exportMarkdown, MdStrings.menuExport),
          ),
        if (!(_c.doc?.note.isDeleted ?? true))
          const PopupMenuItem(
            key: MarkdownKeys.menuRename,
            value: 'rename',
            child: _MenuRow(AppIconKind.rename, MdStrings.menuRename),
          ),
        const PopupMenuItem(
          key: MarkdownKeys.menuInfo,
          value: 'info',
          child: _MenuRow(AppIconKind.info, MdStrings.menuInfo),
        ),
      ],
    );
  }

  List<Widget> _banners() {
    final doc = _c.doc;
    if (doc == null) return const [];
    final out = <Widget>[];
    switch (doc.readOnlyReason) {
      case MarkdownReadOnlyReason.trashed:
        out.add(
          const MdBanner(
            key: MarkdownKeys.bannerTrashed,
            text: MdStrings.bannerTrashed,
          ),
        );
      case MarkdownReadOnlyReason.newerApp:
        out.add(
          const MdBanner(
            key: MarkdownKeys.bannerNewerApp,
            text: MdStrings.bannerNewerApp,
          ),
        );
      case MarkdownReadOnlyReason.bodyMissing:
        out.add(
          MdBanner(
            key: MarkdownKeys.bannerReceiving,
            tone: _receivingLong ? MdBannerTone.warning : MdBannerTone.info,
            text: _receivingLong
                ? MdStrings.bannerReceivingLong
                : MdStrings.bannerReceiving,
          ),
        );
      case null:
        if (_c.tooLargeToEdit) {
          out.add(
            const MdBanner(
              key: MarkdownKeys.bannerTooLargeToEdit,
              text: MdStrings.bannerTooLargeToEdit,
            ),
          );
        }
    }
    if (_c.state == MdSaveState.failed) {
      final tooLarge = _c.failure == MdSaveFailure.tooLarge;
      out.add(
        MdBanner(
          key: tooLarge
              ? MarkdownKeys.bannerTooLarge
              : MarkdownKeys.bannerSaveFailed,
          tone: MdBannerTone.error,
          text: tooLarge
              ? MdStrings.bannerTooLarge
              : MdStrings.bannerSaveFailed,
          actions: [
            TextButton(
              key: MarkdownKeys.bannerRetry,
              onPressed: () => unawaited(_c.flush()),
              child: const Text(MdStrings.retry),
            ),
          ],
        ),
      );
    }
    if (_c.conflictCopyId != null) {
      out.add(
        MdBanner(
          key: MarkdownKeys.bannerConflictCopy,
          tone: MdBannerTone.warning,
          text: MdStrings.bannerConflictCopy,
          actions: [
            if (widget.onOpenMarkdown != null)
              TextButton(
                key: MarkdownKeys.bannerOpenCopy,
                onPressed: () => _openCopy(_c.conflictCopyId!),
                child: const Text(MdStrings.openCopy),
              ),
            TextButton(
              key: MarkdownKeys.bannerDismiss,
              onPressed: _c.dismissConflictCopy,
              child: const Text(MdStrings.dismiss),
            ),
          ],
        ),
      );
    }
    if (_unsaved != null && _c.canEdit) {
      out.add(
        MdBanner(
          key: MarkdownKeys.bannerUnsaved,
          tone: MdBannerTone.warning,
          text: MdStrings.bannerUnsaved,
          actions: [
            TextButton(
              key: MarkdownKeys.bannerUnsavedDiscard,
              onPressed: _discardUnsaved,
              child: const Text(MdStrings.discard),
            ),
            TextButton(
              key: MarkdownKeys.bannerUnsavedRestore,
              onPressed: () => unawaited(_restoreUnsaved()),
              child: const Text(MdStrings.restore),
            ),
          ],
        ),
      );
    }
    return out;
  }

  Widget _body(BuildContext context, _Mode mode, bool narrow) {
    if (_c.loadError != null) {
      return const Center(child: Text(MdStrings.loadFailed));
    }
    if (!_c.loaded) return const SizedBox.shrink();
    if (_c.doc == null) return _notMarkdown(context);
    final editor = _editorMounted
        ? KeyedSubtree(key: _editorKey, child: _editorPane(narrow))
        : null;
    switch (mode) {
      case _Mode.view:
        return Stack(
          children: [
            if (editor != null)
              Offstage(child: TickerMode(enabled: false, child: editor)),
            Positioned.fill(child: _mdView(_view, MarkdownKeys.view)),
          ],
        );
      case _Mode.edit:
        return editor!;
      case _Mode.split:
        final t = StyleTokens.of(context);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: editor!),
            Container(width: 1, color: t.hairline),
            Expanded(
              child: ColoredBox(
                color: t.panel,
                child: _mdView(_preview, MarkdownKeys.splitPreview),
              ),
            ),
          ],
        );
    }
  }

  Widget _mdView(MdViewController controller, Key key) => MdView(
    document: _parsed,
    controller: controller,
    listKey: key,
    highlightBlock: _highlight,
    onLink: _onLink,
    onFootnote: _onFootnote,
    onToggleTask: (i) => unawaited(_toggleTask(i)),
    canToggleTask: _canToggle,
  );

  Widget _editorPane(bool narrow) => Column(
    children: [
      Expanded(
        child: MdEditor(
          controller: _c.text,
          onUndo: _c.undoStep,
          onRedo: _c.redoStep,
          focusNode: _editorFocus,
          readOnly: !_c.canEdit,
        ),
      ),
      MdAccessoryRow(
        controller: _c.text,
        focusNode: _editorFocus,
        undo: narrow ? _c.undo : null,
        onUndo: _c.undoStep,
        onRedo: _c.redoStep,
      ),
    ],
  );

  Widget _notMarkdown(BuildContext context) {
    final t = StyleTokens.of(context);
    final note = ref.watch(noteProvider(widget.noteId)).value;
    final asNote =
        widget.onOpenAsNote != null && note != null && !note.isMarkdown;
    return Center(
      key: MarkdownKeys.notMarkdown,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIconKind.markdownDoc, size: 40, color: t.textSecondary),
            const SizedBox(height: 12),
            Text(
              MdStrings.notMarkdown,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: t.textPrimary),
            ),
            if (asNote) ...[
              const SizedBox(height: 16),
              FilledButton(
                key: MarkdownKeys.openAsNote,
                onPressed: widget.onOpenAsNote,
                child: const Text(MdStrings.openAsNote),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Owns its field controller, so it outlives the dialog's closing animation.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(MdStrings.renameTitle),
    content: TextField(
      key: MarkdownKeys.renameField,
      controller: _field,
      autofocus: true,
      maxLength: 200,
      decoration: const InputDecoration(hintText: MdStrings.renameHint),
      onSubmitted: (v) => Navigator.of(context).pop(v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(MdStrings.cancel),
      ),
      FilledButton(
        key: MarkdownKeys.renameOk,
        onPressed: () => Navigator.of(context).pop(_field.text),
        child: const Text(MdStrings.ok),
      ),
    ],
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final AppIconKind icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [AppIcon(icon, size: 20), const SizedBox(width: 12), Text(label)],
  );
}
