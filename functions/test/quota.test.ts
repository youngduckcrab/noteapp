// The daily cap store (docs/plans/m5-7/07-sync.md 6.8.7): Seoul day keys and MemoryQuotaStore —
// the boundary at cap, Seoul midnight, cap ≤ 0 refused by the store (the handler skips the cap).

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { checkCap, MemoryQuotaStore, seoulDayKey } from "../src/quota.js";

describe("seoulDayKey", () => {
  for (const [iso, key] of [
    ["2026-11-05T14:59:59.999Z", "20261105"],
    ["2026-11-05T15:00:00.000Z", "20261106"],
    ["2026-12-31T14:59:59.999Z", "20261231"],
    ["2026-12-31T15:00:00.000Z", "20270101"],
    ["2028-02-28T15:00:00.000Z", "20280229"],
    ["1970-01-01T00:00:00.000Z", "19700101"],
  ] as const) {
    it(`${iso} → ${key} (UTC+9, no daylight saving)`, () => {
      assert.equal(seoulDayKey(Date.parse(iso)), key);
    });
  }

  it("the same key for the whole Seoul day", () => {
    const start = Date.parse("2026-07-01T15:00:00.000Z");
    for (const offset of [0, 1, 3_600_000, 86_399_999]) {
      assert.equal(seoulDayKey(start + offset), "20260702");
    }
    assert.equal(seoulDayKey(start + 86_400_000), "20260703");
  });
});

describe("MemoryQuotaStore", () => {
  it("allows exactly cap calls a day; at cap the count stays", async () => {
    const q = new MemoryQuotaStore();
    for (let i = 1; i <= 3; i++) {
      assert.deepEqual(await q.take("u1", "20261106", 3), { allowed: true, used: i });
    }
    assert.deepEqual(await q.take("u1", "20261106", 3), { allowed: false, used: 3 });
    assert.deepEqual(await q.take("u1", "20261106", 3), { allowed: false, used: 3 });
    // A larger cap (DAILY_CAP changed) goes on from the same count.
    assert.deepEqual(await q.take("u1", "20261106", 4), { allowed: true, used: 4 });
  });

  it("counts each uid on its own; a new day starts again", async () => {
    const q = new MemoryQuotaStore();
    assert.deepEqual(await q.take("u1", "20261106", 1), { allowed: true, used: 1 });
    assert.deepEqual(await q.take("u1", "20261106", 1), { allowed: false, used: 1 });
    assert.deepEqual(await q.take("u2", "20261106", 1), { allowed: true, used: 1 });
    assert.deepEqual(await q.take("u1", "20261107", 1), { allowed: true, used: 1 });
  });

  it("concurrent takes never pass the cap", async () => {
    const q = new MemoryQuotaStore();
    const results = await Promise.all(Array.from({ length: 7 }, () => q.take("u1", "20261106", 4)));
    assert.equal(results.filter((r) => r.allowed).length, 4);
    assert.deepEqual(
      results.map((r) => r.used),
      [1, 2, 3, 4, 4, 4, 4],
    );
  });

  for (const cap of [0, -1, 1.5, Number.NaN]) {
    it(`cap ${cap} → RangeError (no cap is the handler's DAILY_CAP ≤ 0, never take)`, async () => {
      await assert.rejects(new MemoryQuotaStore().take("u1", "20261106", cap), RangeError);
      assert.throws(() => checkCap(cap), RangeError);
    });
  }
});
