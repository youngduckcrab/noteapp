import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void main() {
  const ok = PersistenceStatus(pendingOps: 0, isWriting: false);
  const failing2 = PersistenceStatus(
    pendingOps: 1,
    isWriting: false,
    consecutiveFailures: 2,
  );
  const failing3 = PersistenceStatus(
    pendingOps: 1,
    isWriting: false,
    consecutiveFailures: 3,
  );
  const durable = StorageInfo(backend: StorageBackend.webSharedIndexedDb);
  const memory = StorageInfo(backend: StorageBackend.webInMemory);

  test('writeFailing wins from 3 consecutive failures', () {
    expect(storageWarningOf(durable, failing3), StorageWarning.writeFailing);
    expect(storageWarningOf(memory, failing3), StorageWarning.writeFailing);
    expect(storageWarningOf(durable, failing2), isNull);
  });

  test('notDurable for in-memory backends', () {
    expect(storageWarningOf(memory, ok), StorageWarning.notDurable);
    expect(
      storageWarningOf(
        const StorageInfo(backend: StorageBackend.nativeMemory),
        failing2,
      ),
      StorageWarning.notDurable,
    );
  });

  test('no warning otherwise', () {
    for (final b in StorageBackend.values) {
      final info = StorageInfo(backend: b);
      final expected =
          b == StorageBackend.webInMemory || b == StorageBackend.nativeMemory
          ? StorageWarning.notDurable
          : null;
      expect(storageWarningOf(info, ok), expected, reason: b.name);
    }
  });

  test('StorageInfo flags', () {
    expect(
      const StorageInfo(backend: StorageBackend.webUnsafeIndexedDb)
          .isMultiTabSafe,
      isFalse,
    );
    expect(durable.isMultiTabSafe, isTrue);
    expect(durable.isDurable, isTrue);
    expect(memory.isDurable, isFalse);
  });
}
