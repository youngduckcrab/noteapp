// The daily cap store (docs/plans/m5-7/07-sync.md 6.8.7): Seoul day keys and MemoryQuotaStore —
// the boundary at cap, Seoul midnight, cap ≤ 0 refused by the store (the handler skips the cap).
// S2-11: FirestoreQuotaStore on an in-memory Firestore stand-in (document shape, refusal writes
// nothing, concurrent takes with transaction retries) and the QUOTA_STORE choice.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  checkCap,
  FirestoreQuotaStore,
  MemoryQuotaStore,
  QUOTA_COLLECTION,
  QUOTA_KEEP_MS,
  QuotaStoreConfigError,
  quotaStoreFor,
  seoulDayKey,
} from "../src/quota.js";
import { FakeFirestore } from "./support/fake_firestore.js";

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

describe("FirestoreQuotaStore (S2-11)", () => {
  const T = Date.parse("2026-11-06T03:00:00.000Z");

  it("one document <uid>_<day> in fnQuota: {count, uid, day, expireAt = +2 days, updatedAt}", async () => {
    const db = new FakeFirestore();
    let now = T;
    const q = new FirestoreQuotaStore(db.asFirestore(), undefined, () => now);
    assert.equal(QUOTA_COLLECTION, "fnQuota");
    assert.deepEqual(await q.take("owner-uid", "20261106", 3), { allowed: true, used: 1 });
    now = T + 60_000;
    assert.deepEqual(await q.take("owner-uid", "20261106", 3), { allowed: true, used: 2 });
    assert.deepEqual([...db.docs.keys()], ["fnQuota/owner-uid_20261106"]);
    const doc = db.docs.get("fnQuota/owner-uid_20261106")!;
    assert.deepEqual(doc.data, {
      count: 2,
      uid: "owner-uid",
      day: "20261106",
      expireAt: new Date(T + 60_000 + QUOTA_KEEP_MS),
      updatedAt: new Date(T + 60_000),
    });
    assert.equal(QUOTA_KEEP_MS, 2 * 86_400_000);
  });

  it("allows exactly cap calls; a refusal writes nothing; a larger cap goes on", async () => {
    const db = new FakeFirestore();
    const q = new FirestoreQuotaStore(db.asFirestore(), undefined, () => T);
    for (let i = 1; i <= 2; i++) {
      assert.deepEqual(await q.take("u1", "20261106", 2), { allowed: true, used: i });
    }
    const before = db.docs.get("fnQuota/u1_20261106")!;
    assert.deepEqual(await q.take("u1", "20261106", 2), { allowed: false, used: 2 });
    assert.equal(db.docs.get("fnQuota/u1_20261106"), before, "the stored document is untouched");
    assert.deepEqual(await q.take("u1", "20261106", 3), { allowed: true, used: 3 });
  });

  it("each uid and each day is its own document; the collection can be named", async () => {
    const db = new FakeFirestore();
    const q = new FirestoreQuotaStore(db.asFirestore(), "quotaTest", () => T);
    await q.take("u1", "20261106", 1);
    assert.deepEqual(await q.take("u1", "20261106", 1), { allowed: false, used: 1 });
    assert.deepEqual(await q.take("u2", "20261106", 1), { allowed: true, used: 1 });
    assert.deepEqual(await q.take("u1", "20261107", 1), { allowed: true, used: 1 });
    assert.deepEqual([...db.docs.keys()].sort(), [
      "quotaTest/u1_20261106",
      "quotaTest/u1_20261107",
      "quotaTest/u2_20261106",
    ]);
  });

  it("concurrent takes never pass the cap (conflicting transactions run again)", async () => {
    const db = new FakeFirestore();
    const q = new FirestoreQuotaStore(db.asFirestore(), undefined, () => T);
    const results = await Promise.all(Array.from({ length: 3 }, () => q.take("u1", "20261106", 2)));
    assert.equal(results.filter((r) => r.allowed).length, 2);
    assert.deepEqual(results.map((r) => r.used).sort(), [1, 2, 2]);
    assert.equal(db.docs.get("fnQuota/u1_20261106")!.data.count, 2);
    assert.ok(db.retries > 0, "the fake made the transactions conflict");
  });

  it("a stored count that is not a positive integer counts as 0", async () => {
    for (const stored of ["7", -3, 1.5, null]) {
      const db = new FakeFirestore();
      db.docs.set("fnQuota/u1_20261106", { data: { count: stored }, version: 1 });
      const q = new FirestoreQuotaStore(db.asFirestore(), undefined, () => T);
      assert.deepEqual(await q.take("u1", "20261106", 5), { allowed: true, used: 1 }, String(stored));
    }
  });

  it("cap ≤ 0 or not an integer → RangeError before any transaction", async () => {
    const db = new FakeFirestore();
    const q = new FirestoreQuotaStore(db.asFirestore());
    await assert.rejects(q.take("u1", "20261106", 0), RangeError);
    assert.equal(db.attempts, 0);
  });
});

describe("quotaStoreFor (QUOTA_STORE)", () => {
  it("'memory' counts in memory and never builds Firestore", async () => {
    let built = 0;
    const q = quotaStoreFor(
      () => "memory",
      () => {
        built++;
        return new FakeFirestore().asFirestore();
      },
    );
    assert.deepEqual(await q.take("u1", "20261106", 1), { allowed: true, used: 1 });
    assert.deepEqual(await q.take("u1", "20261106", 1), { allowed: false, used: 1 });
    assert.equal(built, 0);
  });

  it("'firestore' builds Firestore once, on the first take (not when the module loads)", async () => {
    const db = new FakeFirestore();
    let built = 0;
    let reads = 0;
    const q = quotaStoreFor(
      () => {
        reads++;
        return "firestore";
      },
      () => {
        built++;
        return db.asFirestore();
      },
    );
    assert.equal(reads + built, 0);
    await q.take("u1", "20261106", 2);
    await q.take("u1", "20261106", 2);
    assert.deepEqual([reads, built], [1, 1]);
    assert.equal(db.docs.get("fnQuota/u1_20261106")!.data.count, 2);
  });

  for (const kind of ["", "redis", "Memory"]) {
    it(`'${kind}' → every take rejects with QuotaStoreConfigError (the cap never turns off)`, async () => {
      const q = quotaStoreFor(
        () => kind,
        () => new FakeFirestore().asFirestore(),
      );
      await assert.rejects(q.take("u1", "20261106", 1), QuotaStoreConfigError);
      await assert.rejects(q.take("u1", "20261106", 1), (e: Error) => e.name === "QuotaStoreConfigError");
    });
  }
});
