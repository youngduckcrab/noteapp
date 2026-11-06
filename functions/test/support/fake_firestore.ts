// A small in-memory stand-in for the Admin SDK Firestore surface FirestoreQuotaStore uses
// (collection().doc(), runTransaction with tx.get / tx.set) — unit tests only, no emulator.
// Transactions are optimistic like Firestore's: reads remember the document version, the commit
// fails when a read document changed meanwhile and the body runs again (up to 5 attempts).

import type { Firestore } from "firebase-admin/firestore";

interface StoredDoc {
  data: Record<string, unknown>;
  version: number;
}

interface FakeRef {
  readonly path: string;
}

export class FakeFirestore {
  readonly docs = new Map<string, StoredDoc>();
  /** Transaction bodies run (attempts, including retries). */
  attempts = 0;
  /** Commits refused because a read document changed. */
  retries = 0;

  collection(name: string): { doc(id: string): FakeRef } {
    return { doc: (id: string) => ({ path: `${name}/${id}` }) };
  }

  async runTransaction<T>(body: (tx: unknown) => Promise<T>): Promise<T> {
    for (let attempt = 0; attempt < 5; attempt++) {
      this.attempts++;
      const reads = new Map<string, number>();
      const writes = new Map<string, Record<string, unknown>>();
      const tx = {
        get: async (ref: FakeRef) => {
          const doc = this.docs.get(ref.path);
          reads.set(ref.path, doc?.version ?? 0);
          await Promise.resolve(); // let other transactions interleave
          return { exists: doc !== undefined, get: (field: string) => doc?.data[field] };
        },
        set: (ref: FakeRef, data: Record<string, unknown>) => {
          writes.set(ref.path, structuredClone(data));
          return tx;
        },
      };
      const result = await body(tx);
      await Promise.resolve();
      const stale = [...reads].some(([path, version]) => (this.docs.get(path)?.version ?? 0) !== version);
      if (stale) {
        this.retries++;
        continue;
      }
      for (const [path, data] of writes) {
        this.docs.set(path, { data, version: (this.docs.get(path)?.version ?? 0) + 1 });
      }
      return result;
    }
    throw new Error("ABORTED: too much contention");
  }

  /** This fake typed as the Admin SDK Firestore (only the members above are used). */
  asFirestore(): Firestore {
    return this as unknown as Firestore;
  }
}
