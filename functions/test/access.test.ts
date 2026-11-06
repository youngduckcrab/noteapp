// The owner list (07-sync 6.8.2 step 2, contract 7.3.2 F-1): closed by default.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { isOwner, parseOwnerUids } from "../src/access.js";

describe("parseOwnerUids", () => {
  it("empty or blank → nobody", () => {
    assert.deepEqual(parseOwnerUids(""), []);
    assert.deepEqual(parseOwnerUids("  ,  , "), []);
  });

  it("comma separated, trimmed, empty entries dropped", () => {
    assert.deepEqual(parseOwnerUids("owner-uid"), ["owner-uid"]);
    assert.deepEqual(parseOwnerUids(" a , b,,c "), ["a", "b", "c"]);
  });
});

describe("isOwner", () => {
  it("only an exact uid on the list", () => {
    const owners = parseOwnerUids("owner-uid,second");
    assert.equal(isOwner("owner-uid", owners), true);
    assert.equal(isOwner("second", owners), true);
    assert.equal(isOwner("stranger-uid", owners), false);
    assert.equal(isOwner("Owner-uid", owners), false);
    assert.equal(isOwner("owner", owners), false);
  });

  it("an empty list lets nobody in; no wildcard; an empty uid never passes", () => {
    assert.equal(isOwner("owner-uid", []), false);
    assert.equal(isOwner("anyone", ["*"]), false);
    assert.equal(isOwner("", [""]), false);
  });
});
