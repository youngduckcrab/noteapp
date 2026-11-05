// Shared body of the PenPresetRepository and SettingsRepository rules (CORE 4.5, 6.2.2,
// 6.19). Runs on createFakeNoteStore() (test/repo/preset_contract_fake_test.dart) and on
// openTestNoteStore() (test/repo/pen_preset_repository_test.dart,
// settings_repository_test.dart — CORE T12).
import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

/// Opens a store; [seedDefaultPenPresets] as in createFakeNoteStore / openTestNoteStore.
typedef SeedingStoreFactory = FutureOr<NoteStore> Function({
  required bool seedDefaultPenPresets,
});

const List<String> kDefaultPresetIds = [
  'preset-default-ballpoint',
  'preset-default-fountain',
  'preset-default-highlighter',
  'preset-default-pencil',
  'preset-default-marker',
];

void definePresetContractTests(SeedingStoreFactory open) {
  late NoteStore store;
  late PenPresetRepository presets;
  setUp(() async {
    store = await open(seedDefaultPenPresets: true);
    presets = store.penPresets;
  });
  tearDown(() => store.close());

  test('5 deterministic defaults right after open', () async {
    final list = await presets.getPresets();
    expect(list.map((p) => p.id), kDefaultPresetIds);
    expect(list.map((p) => p.name), ['볼펜', '만년필', '형광펜', '연필', '마커']);
    expect(list.map((p) => p.sortKey), ['a0', 'a1', 'a2', 'a3', 'a4']);
    expect(list.every((p) => p.pinned && p.group == null), isTrue);
    expect(list.every((p) => p.ownerId == store.ownerId), isTrue);
    expect(
      list.every((p) => p.version == const Hlc(1, 0, '0000000000000000')),
      isTrue,
    );
    for (var i = 0; i < 5; i++) {
      expect(list[i].style, StrokeStyle.defaultsFor(PenTool.values[i]));
    }
    expect(await presets.watchPresets().first, list);
  });

  test(
    'ensureDefaults runs once; deleted defaults are never re-created',
    () async {
      await presets.ensureDefaults();
      expect(await presets.getPresets(), hasLength(5));
      await presets.deletePreset('preset-default-pencil');
      await presets.ensureDefaults();
      expect(
        (await presets.getPresets()).map((p) => p.id),
        isNot(contains('preset-default-pencil')),
      );
      await expectLater(
        presets.deletePreset('preset-default-pencil'),
        throwsA(isA<EntityNotFoundException>()),
      );
    },
  );

  test('without seeding there are no presets until ensureDefaults', () async {
    final other = await open(seedDefaultPenPresets: false);
    addTearDown(other.close);
    expect(await other.penPresets.getPresets(), isEmpty);
    await other.penPresets.ensureDefaults();
    expect(
      (await other.penPresets.getPresets()).map((p) => p.id),
      kDefaultPresetIds,
    );
  });

  test('create (after, trimmed, 1..60) / update / reorderPresets', () async {
    final p = await presets.createPreset(
      name: ' 수업용 ',
      style: StrokeStyle.defaultsFor(PenTool.marker),
      after: 'preset-default-ballpoint',
    );
    expect(p.name, '수업용');
    expect(p.version, isNotNull);
    expect((await presets.getPresets())[1], p);
    final last = await presets.createPreset(
      name: 'end',
      style: StrokeStyle.defaultsFor(PenTool.pencil),
      group: 'g',
      pinned: false,
    );
    expect((await presets.getPresets()).last.id, last.id);
    expect(last.group, 'g');
    expect(last.pinned, isFalse);
    await expectLater(
      presets.createPreset(
        name: 'x' * 61,
        style: StrokeStyle.defaultsFor(PenTool.marker),
      ),
      throwsArgumentError,
    );
    await expectLater(
      presets.createPreset(
        name: 'x',
        style: StrokeStyle.defaultsFor(PenTool.marker),
        after: 'missing',
      ),
      throwsA(isA<EntityNotFoundException>()),
    );
    await presets.updatePreset(p.copyWith(name: '시험용', pinned: false));
    final updated = (await presets.getPresets())[1];
    expect(updated.name, '시험용');
    expect(updated.pinned, isFalse);
    expect(updated.version! > p.version!, isTrue);
    await expectLater(
      presets.updatePreset(p.copyWith(name: ' ')),
      throwsArgumentError,
    );

    await presets.reorderPresets(['preset-default-marker', 'nope', p.id]);
    final order = (await presets.getPresets()).map((x) => x.id).toList();
    expect(order, [
      'preset-default-marker',
      p.id,
      'preset-default-ballpoint',
      'preset-default-fountain',
      'preset-default-highlighter',
      'preset-default-pencil',
      last.id,
    ]);
  });

  test('reorderPreset: after / before / to the end', () async {
    await presets.reorderPreset(
      'preset-default-marker',
      before: 'preset-default-ballpoint',
    );
    await presets.reorderPreset(
      'preset-default-ballpoint',
      after: 'preset-default-pencil',
    );
    await presets.reorderPreset('preset-default-fountain');
    expect((await presets.getPresets()).map((p) => p.id), [
      'preset-default-marker',
      'preset-default-highlighter',
      'preset-default-pencil',
      'preset-default-ballpoint',
      'preset-default-fountain',
    ]);
    await expectLater(
      presets.reorderPreset('preset-default-marker', after: 'missing'),
      throwsArgumentError,
    );
  });

  test('watchPresets re-emits after a change only', () async {
    final values = <List<PenPreset>>[];
    final sub = presets.watchPresets().listen(values.add);
    await pumpEventQueue();
    expect(values, hasLength(1));
    await store.library.createNote(title: 'unrelated');
    await pumpEventQueue();
    expect(values, hasLength(1));
    await presets.deletePreset('preset-default-marker');
    await pumpEventQueue();
    expect(values, hasLength(2));
    expect(values.last, hasLength(4));
    await sub.cancel();
  });
}

void defineSettingsContractTests(SeedingStoreFactory open) {
  late NoteStore store;
  late SettingsRepository settings;
  setUp(() async {
    store = await open(seedDefaultPenPresets: false);
    settings = store.settings;
  });
  tearDown(() => store.close());

  test('typed round trips, including stringList and jsonMap', () async {
    final b = SettingKey.boolean('editor.flag', false);
    final i = SettingKey.integer('editor.count', 3);
    final d = SettingKey.number('editor.ratio', 0.5);
    final s = SettingKey.string('library.viewMode', 'grid');
    final il = SettingKey.intList('editor.recentColors', const []);
    final sl = SettingKey.stringList('library.recentSearches', const []);
    final jm = SettingKey.jsonMap('editor.toolbar');
    expect(await settings.get(b), isFalse);
    expect(await settings.get(i), 3);
    expect(await settings.get(jm), isEmpty);
    await settings.set(b, true);
    await settings.set(i, 7);
    await settings.set(d, 2.0);
    await settings.set(s, 'list');
    await settings.set(il, [0xFF000000, 2]);
    await settings.set(sl, ['a', '강의']);
    await settings.set(jm, {
      'order': ['pen', 'eraser'],
      'size': 1.5,
    });
    expect(await settings.get(b), isTrue);
    expect(await settings.get(i), 7);
    expect(await settings.get(d), 2.0);
    expect(await settings.get(s), 'list');
    expect(await settings.get(il), [0xFF000000, 2]);
    expect(await settings.get(sl), ['a', '강의']);
    expect(await settings.get(jm), {
      'order': ['pen', 'eraser'],
      'size': 1.5,
    });
  });

  test('an undecodable stored value reads as the default', () async {
    await settings.set(SettingKey.string('editor.mixed', ''), 'text');
    expect(await settings.get(SettingKey.integer('editor.mixed', 42)), 42);
    expect(
      await settings.get(SettingKey.stringList('editor.mixed', const ['d'])),
      ['d'],
    );
    final snap = await settings.watchAll().first;
    expect(snap.get(SettingKey.integer('editor.mixed', 9)), 9);
  });

  test(
    'device scope, reset, watch distinct, watchAll, sync. rejected',
    () async {
      final key = SettingKey.intList('editor.recentColors', const []);
      final device = SettingKey.boolean(
        'editor.penOnlyMode',
        false,
        scope: SettingScope.device,
      );
      final seen = <List<int>>[];
      final sub = settings.watch(key).listen(seen.add);
      final deviceSeen = <bool>[];
      final sub2 = settings.watch(device).listen(deviceSeen.add);
      await pumpEventQueue();
      await settings.set(key, [1, 2]);
      await settings.set(key, [1, 2]);
      await settings.set(device, true);
      expect(await settings.get(key), [1, 2]);
      expect(await settings.get(device), isTrue);
      final snap = await settings.watchAll().first;
      expect(snap.get(key), [1, 2]);
      expect(snap.get(device), isTrue);
      expect(snap.raw.keys.toSet(), {
        'editor.recentColors',
        'editor.penOnlyMode',
      });
      await settings.reset(key);
      await settings.reset(device);
      expect(await settings.get(key), isEmpty);
      expect(await settings.get(device), isFalse);
      await pumpEventQueue();
      expect(seen, [
        <int>[],
        [1, 2],
        <int>[],
      ]);
      expect(deviceSeen, [false, true, false]);
      expect((await settings.watchAll().first).raw, isEmpty);
      await settings.set(key, [3]);
      expect(await settings.get(key), [3], reason: 'set after reset');
      await expectLater(
        settings.set(SettingKey.string('sync.cursor', ''), 'x'),
        throwsArgumentError,
      );
      await expectLater(
        settings.get(SettingKey.string('Bad name', '')),
        throwsArgumentError,
      );
      expect(
        () => settings.watch(SettingKey.string('sync.x', '')),
        throwsArgumentError,
      );
      await sub.cancel();
      await sub2.cancel();
    },
  );
}
