// The daily cap of recognizeMath (docs/plans/m5-7/07-sync.md 4.5, 6.8.7 — D-S6): one count per
// user (uid) and Seoul day (UTC+9, no daylight saving). The handler takes one count right
// before the engine call (6.8.2 step 5) and only when DAILY_CAP > 0; a failed engine call keeps
// its count (abuse guard).
//
// S2-10b: the port, MemoryQuotaStore (emulator and unit tests — QUOTA_STORE=memory) and
// seoulDayKey. FirestoreQuotaStore (collection 'fnQuota', Admin SDK transaction) is S2-11.

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
