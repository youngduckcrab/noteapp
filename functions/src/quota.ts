// The daily cap of recognizeMath (docs/plans/m5-7/07-sync.md 4.5, 6.8.7 — D-S6): one count per
// user (uid) and Seoul day (UTC+9, no daylight saving). The handler takes one count right
// before the engine call (6.8.2 step 5) and only when DAILY_CAP > 0; a failed engine call keeps
// its count (abuse guard).
//
// QUOTA_STORE picks the store (quotaStoreFor): 'memory' → MemoryQuotaStore (emulator and unit
// tests — one function process), 'firestore' → FirestoreQuotaStore (production — top-level
// collection 'fnQuota', one document per uid and day, Admin SDK transaction; the 1st-round
// firestore.rules have no match for it, so clients are denied and only the Admin SDK reaches it).

import type { Firestore } from "firebase-admin/firestore";

export interface QuotaStore {
  /** Atomically counts one call of [uid] on [dayKey]; allowed false (count unchanged) at [cap].
   *  [used] is the count after the call (when allowed) or the current count (when refused).
   *  [cap] must be ≥ 1 (the handler does not call take when DAILY_CAP ≤ 0): RangeError otherwise. */
  take(uid: string, dayKey: string, cap: number): Promise<{ allowed: boolean; used: number }>;
}

/** In-memory counts (one function process). Keeps only the latest day of each uid. */
export class MemoryQuotaStore implements QuotaStore {
  private readonly days = new Map<string, { day: string; count: number }>();

  async take(uid: string, dayKey: string, cap: number): Promise<{ allowed: boolean; used: number }> {
    checkCap(cap);
    const entry = this.days.get(uid);
    const used = entry !== undefined && entry.day === dayKey ? entry.count : 0;
    if (used >= cap) return { allowed: false, used };
    this.days.set(uid, { day: dayKey, count: used + 1 });
    return { allowed: true, used: used + 1 };
  }
}

/** The default collection of FirestoreQuotaStore (6.8.7). */
export const QUOTA_COLLECTION = "fnQuota";

/** How long a day document is kept after its last write (Firestore TTL on expireAt — 6.10). */
export const QUOTA_KEEP_MS = 2 * 24 * 60 * 60 * 1000;

/** Counts in Firestore: document `<uid>_<yyyymmdd>` of [collection] =
 *  {count, uid, day, expireAt (last write + 2 days), updatedAt}. One transaction per take: read
 *  → refuse at count ≥ cap (nothing written) → write count + 1. Firestore retries the transaction
 *  on contention, so concurrent calls never count past cap. */
export class FirestoreQuotaStore implements QuotaStore {
  constructor(
    private readonly db: Firestore,
    private readonly collection: string = QUOTA_COLLECTION,
    private readonly now: () => number = () => Date.now(),
  ) {}

  async take(uid: string, dayKey: string, cap: number): Promise<{ allowed: boolean; used: number }> {
    checkCap(cap);
    const ref = this.db.collection(this.collection).doc(`${uid}_${dayKey}`);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const stored: unknown = snap.exists ? snap.get("count") : 0;
      const used = typeof stored === "number" && Number.isInteger(stored) && stored > 0 ? stored : 0;
      if (used >= cap) return { allowed: false, used };
      const at = this.now();
      tx.set(ref, {
        count: used + 1,
        uid,
        day: dayKey,
        expireAt: new Date(at + QUOTA_KEEP_MS),
        updatedAt: new Date(at),
      });
      return { allowed: true, used: used + 1 };
    });
  }
}

/** The store QUOTA_STORE names: 'memory' or 'firestore' ([firestore] is called once, on the
 *  first take). Any other value → a store whose take rejects (the handler answers unavailable
 *  and logs quotaError — a typo never turns the cap off). Read lazily so the parameter is read
 *  at call time, not when the module loads (deploy analysis). */
export function quotaStoreFor(kind: () => string, firestore: () => Firestore): QuotaStore {
  let store: QuotaStore | undefined;
  return {
    take(uid, dayKey, cap) {
      if (store === undefined) {
        const k = kind();
        if (k === "memory") store = new MemoryQuotaStore();
        else if (k === "firestore") store = new FirestoreQuotaStore(firestore());
        else return Promise.reject(new QuotaStoreConfigError(`QUOTA_STORE '${k}' is not memory or firestore`));
      }
      return store.take(uid, dayKey, cap);
    },
  };
}

/** QUOTA_STORE has a value quotaStoreFor does not know. */
export class QuotaStoreConfigError extends Error {
  override readonly name = "QuotaStoreConfigError";
}

/** RangeError unless [cap] is an integer ≥ 1. */
export function checkCap(cap: number): void {
  if (!Number.isInteger(cap) || cap < 1) throw new RangeError(`cap must be an integer ≥ 1, got ${cap}`);
}

const SEOUL_OFFSET_MS = 9 * 60 * 60 * 1000;

/** 'yyyymmdd' of [epochMs] in Seoul (UTC+9, no daylight saving). */
export function seoulDayKey(epochMs: number): string {
  const d = new Date(epochMs + SEOUL_OFFSET_MS);
  const yyyy = String(d.getUTCFullYear()).padStart(4, "0");
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(d.getUTCDate()).padStart(2, "0");
  return `${yyyy}${mm}${dd}`;
}
