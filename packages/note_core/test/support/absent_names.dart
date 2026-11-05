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

// (v2.0, m5-7/02-core 4.11) 2nd-round test / developer helpers live in testing.dart,
// testing_web.dart and dev_tools.dart; internals stay under src/.
final class PageObjectFixtures {}

final class FakeAudioRecorder {}

final class FakeAudioPlayback {}

const Absent openWebTestNoteStore = Absent();
const Absent deleteWebTestNoteStore = Absent();

final class V1DatabaseCopyInfo {}

const Absent v1DatabaseCopyInfo = Absent();
const Absent readV1DatabaseCopy = Absent();
const Absent deleteV1DatabaseCopy = Absent();

final class DriftSearchIndex {}

final class MemorySearchIndex {}

final class SearchIndexer {}

final class FileBlobDatabase {}

final class SearchRectsCodec {}

const Absent upgradeV1ToV2 = Absent();
const Absent searchMatches = Absent();
const Absent ftsCandidateMatches = Absent();
const Absent canonicalDump = Absent();
const Absent kCalligraphyNibAngleKey = Absent();

// B2-α internals (02-core 8.1 'B2 상태').
const Absent notYet = Absent();

final class EmptyRecordingRepository {}

final class EmptyRecordingDraftStore {}

final class EmptyHandwritingRepository {}

final class EmptySearchIndex {}
