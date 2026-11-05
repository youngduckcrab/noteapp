// Names that must NOT be visible through package:note_core/note_core.dart. The API surface
// test imports this library next to the barrel without a prefix and refers to every name:
// if the barrel exported one of them, the reference would be ambiguous and the test would
// not compile (contract 7.2.2 / 7.2.3 / 7.2.7 / 7.2.10 'Removed', 7.1 rule 2).

/// Marker type of the absence checks.
final class Absent {
  const Absent();
}

// Removed from the draft by the contract.
final class StrokeEraseSession {}

final class StorageUnavailableException {}

const Absent kDefaultPressure = Absent();

// Test / developer entry points live in their own libraries, not in the barrel.
const Absent createFakeNoteStore = Absent();

final class FakeNoteStoreFaults {}

final class StrokeFixtures {}

const Absent newerVersionWinsPolicy = Absent();
const Absent openTestNoteStore = Absent();
const Absent seedSyntheticNote = Absent();

// Internal helpers stay under src/.
const Absent normalizeForSearch = Absent();
const Absent readVersion = Absent();

final class SessionEngine {}

final class CommandResolver {}

final class EditHistory {}

final class FakeNoteStore {}

const Absent checkSettingKeyName = Absent();
const Absent decodeSetting = Absent();
const Absent planSortKeys = Absent();
