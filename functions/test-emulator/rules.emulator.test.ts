// SYNC's 1st-round security rules (packages/sync_engine/firebase/firestore.rules, storage.rules)
// in the Auth + Firestore + Storage emulators (docs/plans/m5-7/07-sync.md 6.10 L4 — the "full
// rules check in the emulator" the 1st round left optional, before the first deploy). Requests
// go over REST with real Auth emulator ID tokens, the way the clients send them: Firestore
// documents:commit (the chunk's `su` as the REQUEST_TIME transform, like FieldValue
// .serverTimestamp()), Firebase Storage v0 multipart uploads with the custom metadata `sha256`.
//
// Run by `npm run test:rules` (scripts/rules_suite.sh — firebase emulators:exec with
// test-emulator/firebase.rules-test.json, under the heavy test lock; Java, manual, not in CI —
// Q6). `npm run test:emulator` (functions + auth only) also finds this file: without the
// Firestore and Storage emulators every test here is skipped.
//
// R1–R7 Firestore: own profile and device documents only, with their key lists; chunks — the
// field checks of validChunk, id = <by>-<24 hex>, su = request.time, a rewrite of the same id may
// change su only, delete own (compaction); no profile delete; nothing outside users/{uid}.
// R8–R11 Storage: users/{uid}/assets/{sha256}: own uid, a 64-hex name equal to the sha256
// metadata, read and delete own. Not checkable in the emulator: the 300 MiB size limit (too
// big to send) and "no overwrite" (see R11); the rule text of both is in the Dart
// rules_ownership_test, and the deployed rules are checked in the mini round (L4).

import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { before, describe, it } from "node:test";

const PROJECT = "demo-noteapp";
const BUCKET = `${PROJECT}.appspot.com`;
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST;
const STORAGE_HOST = (process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? "").replace(/^https?:\/\//, "");
const PASSWORD = "test-password";
const SKIP =
  FIRESTORE_HOST === undefined || STORAGE_HOST === ""
    ? "the Firestore and Storage emulators are not running (npm run test:rules)"
    : false;

const DOCS = `http://${FIRESTORE_HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;
const OWNER = "owner-uid";
const STRANGER = "stranger-uid";

// ---- Auth emulator (the conventions of 07-sync 6.8.11) ----------------------------------------

async function postJson(url: string, body: unknown, headers: Record<string, string> = {}): Promise<Response> {
  return fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

/** Makes [uid] in the Auth emulator (or finds it already there) and returns its ID token. */
async function signedInToken(uid: string): Promise<string> {
  const email = `${uid}@example.test`;
  const created = await postJson(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts`,
    { localId: uid, email, password: PASSWORD },
    { Authorization: "Bearer owner" },
  );
  if (!created.ok) {
    const text = await created.text();
    if (!text.includes("DUPLICATE_LOCAL_ID") && !text.includes("EMAIL_EXISTS")) {
      throw new Error(`could not make ${uid}: ${created.status} ${text}`);
    }
  }
  const signIn = await postJson(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    { email, password: PASSWORD, returnSecureToken: true },
  );
  const json = (await signIn.json()) as { idToken?: string };
  if (!signIn.ok || typeof json.idToken !== "string") {
    throw new Error(`could not sign in ${uid}: ${signIn.status} ${JSON.stringify(json)}`);
  }
  return json.idToken;
}

// ---- Firestore REST ---------------------------------------------------------------------------

type Value =
  | { stringValue: string }
  | { integerValue: string }
  | { bytesValue: string }
  | { timestampValue: string }
  | { booleanValue: boolean };
type Fields = Record<string, Value>;

const str = (v: string): Value => ({ stringValue: v });
const int = (v: number): Value => ({ integerValue: String(v) });
const time = (v: string): Value => ({ timestampValue: v });

interface Result {
  status: number;
  text: string;
}

function authHeader(token: string | undefined): Record<string, string> {
  return token === undefined ? {} : { Authorization: `Bearer ${token}` };
}

/**
 * One write through documents:commit. [create] → the document must not exist, false → it must.
 * [serverTime] fields get the REQUEST_TIME transform (FieldValue.serverTimestamp()).
 */
async function write(
  path: string,
  fields: Fields,
  token: string | undefined,
  { create = true, serverTime = [] as string[] } = {},
): Promise<Result> {
  const response = await postJson(
    `${DOCS}:commit`,
    {
      writes: [
        {
          update: { name: `projects/${PROJECT}/databases/(default)/documents/${path}`, fields },
          currentDocument: { exists: !create },
          updateTransforms: serverTime.map((fieldPath) => ({ fieldPath, setToServerValue: "REQUEST_TIME" })),
        },
      ],
    },
    authHeader(token),
  );
  return { status: response.status, text: await response.text() };
}

async function read(path: string, token: string | undefined): Promise<Result> {
  const response = await fetch(`${DOCS}/${path}`, { headers: authHeader(token) });
  return { status: response.status, text: await response.text() };
}

async function remove(path: string, token: string | undefined): Promise<Result> {
  const response = await fetch(`${DOCS}/${path}`, { method: "DELETE", headers: authHeader(token) });
  return { status: response.status, text: await response.text() };
}

function allowed(r: Result, what: string): void {
  assert.equal(r.status, 200, `${what}: ${r.text}`);
}

function denied(r: Result, what: string): void {
  assert.equal(r.status, 403, `${what}: ${r.text}`);
  assert.match(r.text, /PERMISSION_DENIED/, what);
}

const NODE = "a1b2c3d4e5f60718";
const MAX_HLC = `${"0".repeat(15)}-0000-${NODE}`; // 37 characters, the rule's size

let serial = 0;
/** A fresh chunk id of [by]: <by>-<24 hex>. */
function chunkId(by = NODE): string {
  serial++;
  return `${by}-${serial.toString(16).padStart(24, "0")}`;
}

/** The fields of a valid chunk of [by] (without su — the commit sets it). */
function chunk(by = NODE, over: Fields = {}): Fields {
  const data = randomBytes(64);
  return {
    fmt: int(1),
    scope: str("note-1"),
    by: str(by),
    n: int(3),
    bytes: int(data.length),
    maxHlc: str(MAX_HLC),
    kind: str("delta"),
    data: { bytesValue: data.toString("base64") },
    ...over,
  };
}

const profile = (): Fields => ({
  email: str("owner-uid@example.test"),
  displayName: str("Owner"),
  createdAt: int(1),
  lastSeenAt: int(2),
  schema: int(1),
});

// ---- Storage (Firebase v0 API) ----------------------------------------------------------------

const sha256 = (bytes: Buffer): string => createHash("sha256").update(bytes).digest("hex");

function objectUrl(path: string): string {
  return `http://${STORAGE_HOST}/v0/b/${BUCKET}/o/${encodeURIComponent(path)}`;
}

/** A multipart upload of [bytes] to [path] with the custom metadata {sha256: [hash]}. */
async function upload(path: string, bytes: Buffer, hash: string, token: string | undefined): Promise<Result> {
  const boundary = `rules-test-${randomBytes(8).toString("hex")}`;
  const metadata = JSON.stringify({ name: path, contentType: "application/octet-stream", metadata: { sha256: hash } });
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=utf-8\r\n\r\n${metadata}\r\n`),
    Buffer.from(`--${boundary}\r\nContent-Type: application/octet-stream\r\n\r\n`),
    bytes,
    Buffer.from(`\r\n--${boundary}--`),
  ]);
  const response = await fetch(`http://${STORAGE_HOST}/v0/b/${BUCKET}/o?name=${encodeURIComponent(path)}`, {
    method: "POST",
    headers: {
      "Content-Type": `multipart/related; boundary=${boundary}`,
      "X-Goog-Upload-Protocol": "multipart",
      ...(token === undefined ? {} : { Authorization: `Firebase ${token}` }),
    },
    body,
  });
  return { status: response.status, text: await response.text() };
}

async function download(path: string, token: string | undefined): Promise<Result> {
  const response = await fetch(`${objectUrl(path)}?alt=media`, {
    headers: token === undefined ? {} : { Authorization: `Firebase ${token}` },
  });
  return { status: response.status, text: await response.text() };
}

async function deleteObject(path: string, token: string | undefined): Promise<Result> {
  const response = await fetch(objectUrl(path), {
    method: "DELETE",
    headers: token === undefined ? {} : { Authorization: `Firebase ${token}` },
  });
  return { status: response.status, text: await response.text() };
}

/** Storage denials are 403 (a missing object would be 404 — the tests only ask for existing ones). */
function storageDenied(r: Result, what: string): void {
  assert.equal(r.status, 403, `${what}: ${r.text}`);
}

function storageAllowed(r: Result, what: string): void {
  assert.ok(r.status === 200 || r.status === 204, `${what}: ${r.status} ${r.text}`);
}

// ---- the rules --------------------------------------------------------------------------------

describe("security rules in the emulators (07-sync 6.10 L4)", { skip: SKIP }, () => {
  let owner = "";
  let stranger = "";

  before(async () => {
    owner = await signedInToken(OWNER);
    stranger = await signedInToken(STRANGER);
  });

  it("R1 the own profile document: create and read with its keys; another uid, no token, an extra key or a delete → denied", async () => {
    denied(await write(`users/${OWNER}`, profile(), undefined), "no token");
    denied(await write(`users/${OWNER}`, profile(), stranger), "another uid");
    denied(await write(`users/${OWNER}`, { ...profile(), plan: str("pro") }, owner), "extra key");
    allowed(await write(`users/${OWNER}`, profile(), owner), "own profile");
    allowed(await write(`users/${OWNER}`, { ...profile(), lastSeenAt: int(3) }, owner, { create: false }), "update");
    allowed(await read(`users/${OWNER}`, owner), "read own");
    denied(await read(`users/${OWNER}`, stranger), "read another uid's");
    denied(await remove(`users/${OWNER}`, owner), "delete");
  });

  it("R2 devices: own uid, a 16-hex node id and the device keys; delete own", async () => {
    const device = (): Fields => ({
      platform: str("web"),
      appVersion: str("2.0.0"),
      firstSeenAt: int(1),
      lastSeenAt: int(2),
      cursorMicros: int(0),
    });
    allowed(await write(`users/${OWNER}/devices/${NODE}`, device(), owner), "own device");
    denied(await write(`users/${OWNER}/devices/not-a-node-id`, device(), owner), "bad node id");
    denied(await write(`users/${OWNER}/devices/b1b2c3d4e5f60718`, { ...device(), token: str("x") }, owner), "extra key");
    denied(await write(`users/${STRANGER}/devices/${NODE}`, device(), owner), "another uid");
    denied(await read(`users/${OWNER}/devices/${NODE}`, stranger), "read another uid's");
    allowed(await remove(`users/${OWNER}/devices/${NODE}`, owner), "delete own");
  });

  it("R3 a valid chunk with su = request.time is created; read by its owner only", async () => {
    const id = chunkId();
    allowed(await write(`users/${OWNER}/changes/${id}`, chunk(), owner, { serverTime: ["su"] }), "valid chunk");
    allowed(await read(`users/${OWNER}/changes/${id}`, owner), "read own");
    denied(await read(`users/${OWNER}/changes/${id}`, stranger), "read another uid's");
    denied(await write(`users/${STRANGER}/changes/${chunkId()}`, chunk(), owner, { serverTime: ["su"] }), "another uid");
    denied(await write(`users/${OWNER}/changes/${chunkId()}`, chunk(), undefined, { serverTime: ["su"] }), "no token");
  });

  it("R4 su must be the server's request time: a client time or none → denied", async () => {
    denied(
      await write(`users/${OWNER}/changes/${chunkId()}`, { ...chunk(), su: time("2026-01-01T00:00:00Z") }, owner),
      "client time",
    );
    denied(await write(`users/${OWNER}/changes/${chunkId()}`, chunk(), owner), "no su");
  });

  it("R5 validChunk field checks and the id rule", async () => {
    const bad: [string, Fields, string?][] = [
      ["fmt 0", chunk(NODE, { fmt: int(0) })],
      ["fmt 17", chunk(NODE, { fmt: int(17) })],
      ["empty scope", chunk(NODE, { scope: str("") })],
      ["scope of 65", chunk(NODE, { scope: str("s".repeat(65)) })],
      ["by not 16 hex", chunk("NOT-HEX-NODE-ID!"), `NOT-HEX-NODE-ID!-${"0".repeat(24)}`],
      ["n 0", chunk(NODE, { n: int(0) })],
      ["n 5001", chunk(NODE, { n: int(5001) })],
      ["bytes ≠ data size", chunk(NODE, { bytes: int(65) })],
      ["maxHlc of 36", chunk(NODE, { maxHlc: str(MAX_HLC.slice(1)) })],
      ["kind other", chunk(NODE, { kind: str("other") })],
      ["extra key", chunk(NODE, { extra: int(1) })],
      ["data not bytes", chunk(NODE, { data: str("AAAA") })],
      ["id prefix ≠ by", chunk(NODE), chunkId("b1b2c3d4e5f60718")],
      ["id not <by>-<24 hex>", chunk(NODE), `${NODE}-xyz`],
    ];
    for (const [what, fields, id] of bad) {
      denied(await write(`users/${OWNER}/changes/${id ?? chunkId()}`, fields, owner, { serverTime: ["su"] }), what);
    }
  });

  it("R6 the same id again: identical content with a new su is allowed (lost-ack retry); any other change → denied", async () => {
    const id = chunkId();
    const fields = chunk();
    allowed(await write(`users/${OWNER}/changes/${id}`, fields, owner, { serverTime: ["su"] }), "create");
    allowed(
      await write(`users/${OWNER}/changes/${id}`, fields, owner, { create: false, serverTime: ["su"] }),
      "retry with su only",
    );
    denied(
      await write(`users/${OWNER}/changes/${id}`, { ...fields, n: int(4) }, owner, { create: false, serverTime: ["su"] }),
      "retry that changes n",
    );
    denied(
      await write(`users/${OWNER}/changes/${id}`, fields, stranger, { create: false, serverTime: ["su"] }),
      "retry by another uid",
    );
  });

  it("R7 compaction deletes own chunks; another uid cannot; nothing outside users/{uid}", async () => {
    const id = chunkId();
    allowed(await write(`users/${OWNER}/changes/${id}`, chunk(), owner, { serverTime: ["su"] }), "create");
    denied(await remove(`users/${OWNER}/changes/${id}`, stranger), "delete by another uid");
    allowed(await remove(`users/${OWNER}/changes/${id}`, owner), "delete own");
    denied(await write(`fnQuota/${OWNER}_20261106`, { count: int(1) }, owner), "fnQuota (Admin SDK only)");
    denied(await write("other/doc", { a: int(1) }, owner), "another collection");
  });

  it("R8 an own asset whose name is the sha256 of its bytes (metadata sha256) is stored and read back by its owner only", async () => {
    const bytes = randomBytes(256);
    const id = sha256(bytes);
    const path = `users/${OWNER}/assets/${id}`;
    storageAllowed(await upload(path, bytes, id, owner), "own asset");
    const back = await download(path, owner);
    storageAllowed(back, "read own");
    storageDenied(await download(path, stranger), "read another uid's");
    storageDenied(await download(path, undefined), "read without a token");
  });

  it("R9 the sha256 metadata must equal the name, and the name must be 64 hex", async () => {
    const bytes = randomBytes(128);
    const id = sha256(bytes);
    storageDenied(await upload(`users/${OWNER}/assets/${id}`, bytes, sha256(randomBytes(8)), owner), "other sha256");
    storageDenied(await upload(`users/${OWNER}/assets/${id.toUpperCase()}`, bytes, id.toUpperCase(), owner), "upper-case hex");
    storageDenied(await upload(`users/${OWNER}/assets/not-a-hash`, bytes, "not-a-hash", owner), "not a hash");
  });

  it("R10 another uid's path or no token → denied", async () => {
    const bytes = randomBytes(64);
    const id = sha256(bytes);
    storageDenied(await upload(`users/${STRANGER}/assets/${id}`, bytes, id, owner), "another uid");
    storageDenied(await upload(`users/${OWNER}/assets/${id}`, bytes, id, undefined), "no token");
    storageDenied(await upload(`elsewhere/${id}`, bytes, id, owner), "outside users/{uid}/assets");
  });

  // `allow update: if false` (no overwrite) is not checked here: the Storage emulator of
  // firebase-tools 15.34.1 judges every upload as `create`, an existing object too
  // (lib/emulator/storage/files.js — RulesetOperationMethod.CREATE with `before` set), so an
  // overwrite passes the create rule. Checked after the first deploy (mini round L4).
  it("R11 delete own only", async () => {
    const bytes = randomBytes(96);
    const id = sha256(bytes);
    const path = `users/${OWNER}/assets/${id}`;
    storageAllowed(await upload(path, bytes, id, owner), "create");
    storageDenied(await deleteObject(path, stranger), "delete by another uid");
    storageAllowed(await deleteObject(path, owner), "delete own");
  });
});
