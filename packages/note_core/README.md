# note_core

Owned by CORE: document model, local storage, undo, sync outbox. Plan:
[docs/plans/02-core.md](../../docs/plans/02-core.md), contract:
[00-overview.md 7장](../../docs/plans/00-overview.md) (7.2.2 ~ 7.2.14, 7.6 B2).

Pure Dart, web safe. Entry points:

| Import | Use |
|---|---|
| `package:note_core/note_core.dart` | Everything public: data types, commands, `NoteSession`, repositories, `SyncStore`, `AssetStore`, providers |
| `package:note_core/dev_tools.dart` | `seedSyntheticNote` (developer menu) |
| `package:note_core/testing.dart` | `test/` only: `createFakeNoteStore`, `FakeNoteStoreFaults`, `StrokeFixtures`, `newerVersionWinsPolicy` |
| `package:note_core/testing_vm.dart` | VM `test/` only: `openTestNoteStore` |

Foundation step B2 state: the contract types, the in-memory session engine and
`createFakeNoteStore()` work. `openNoteStore`, `deleteLocalNoteData`,
`openTestNoteStore` and the fake store's `exportBackupJson` throw
`UnimplementedError` until CORE T6 / T19 (contract 7.6).

Test setup in other areas:

```dart
final store = createFakeNoteStore();
final container = ProviderContainer.test(
  overrides: [noteStoreProvider.overrideWithValue(store)],
);
```

Riverpod 3 pauses providers without listeners: keep a listener
(`container.listen(provider.future, (_, _) {})`) while awaiting a
stream-backed provider in tests.
