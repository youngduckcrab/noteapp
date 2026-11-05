// Helpers of the CORE storage tests (T7+): a real in-memory store and small entities.
import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing_vm.dart';

import '../shared/entity_samples.dart';

const String kTestNode = '00000000000000aa';

Future<DriftNoteStore> openStore({Clock? clock, String? filePath}) async =>
    await openTestNoteStore(
      clock: clock,
      ids: SequentialIdGenerator(),
      deviceNodeId: kTestNode,
      filePath: filePath,
      seedDefaultPenPresets: false,
    ) as DriftNoteStore;

Folder folder(String id, {String name = 'F', FolderId? parentId}) => Folder(
  id: id,
  ownerId: kLocalOwnerId,
  parentId: parentId,
  name: name,
  sortKey: 'a0',
  createdAt: 1,
  updatedAt: 1,
);

Note note(String id, {String title = 'N', int pageCount = 0}) => Note(
  id: id,
  ownerId: kLocalOwnerId,
  title: title,
  sortKey: 'a0',
  createdAt: 1,
  updatedAt: 1,
  pageCount: pageCount,
);

Page page(String id, NoteId noteId, {int contentRevision = 0}) => Page(
  id: id,
  noteId: noteId,
  sortKey: 'a0',
  size: PageSize.a4Portrait,
  background: const BlankBackground(),
  createdAt: 1,
  updatedAt: 1,
  contentRevision: contentRevision,
);

Stroke stroke(String id, PageId pageId, {EpochMillis? deletedAt}) => Stroke(
  id: id,
  pageId: pageId,
  style: StrokeStyle.defaultsFor(PenTool.ballpoint),
  points: kG1Points,
  createdAt: 1,
  deletedAt: deletedAt,
);

Recording recording(String id, NoteId noteId) => Recording(
  id: id,
  noteId: noteId,
  assetId: 'a' * 64,
  durationMs: 1000,
  startedAt: 1,
  createdAt: 1,
  updatedAt: 1,
);
