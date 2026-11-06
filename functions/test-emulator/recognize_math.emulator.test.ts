// recognizeMath in the functions + auth emulators (docs/plans/m5-7/07-sync.md 6.8.11, V13 SYNC
// side): E1–E10 over the callable HTTP protocol with Node fetch. Run by `npm run test:emulator`
// (scripts/emulator_suite.sh — `firebase emulators:exec --only functions,auth --project
// demo-noteapp`), never by `npm test`. Demo parameters: functions/.env.demo-noteapp
// (OWNER_UIDS=owner-uid, MATH_ENGINE=fake, ALLOW_FAKE_ENGINE=true, QUOTA_STORE=memory).
//
// Conventions shared with LIBRARY's Dart emulator test (05-library L2-I6): project demo-noteapp,
// users owner-uid / stranger-uid (<uid>@example.test, password test-password) made through the
// Auth emulator admin REST (Authorization: Bearer owner, localId); a user that already exists is
// just signed in, so the two languages' tests may run in either order in one emulator run.
// The fake engine values are contract 7.6 (src/engines/fake.ts).

import assert from "node:assert/strict";
import { before, describe, it } from "node:test";

const PROJECT = "demo-noteapp";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
const FUNCTION_URL = `http://127.0.0.1:5001/${PROJECT}/asia-northeast3/recognizeMath`;
const PASSWORD = "test-password";

/** A 1×1 grayscale PNG, 67 bytes (fake engine → \sqrt{67}). */
const PNG_67 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mNgAAAAAgAB5Sfe/AAAAABJRU5ErkJggg==";

interface CallResult {
  status: number;
  body: { result?: Record<string, unknown>; error?: { status?: string; message?: string } };
}

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

/** One callable request ({data} in, {result} or {error} out). */
async function call(data: unknown, token?: string): Promise<CallResult> {
  const response = await postJson(
    FUNCTION_URL,
    { data },
    token === undefined ? {} : { Authorization: `Bearer ${token}` },
  );
  return { status: response.status, body: (await response.json()) as CallResult["body"] };
}

function assertError(r: CallResult, status: number, code: string): void {
  assert.equal(r.status, status, JSON.stringify(r.body));
  assert.equal(r.body.error?.status, code, JSON.stringify(r.body));
  assert.equal(r.body.result, undefined);
}

/** Two strokes, five points in total (fake engine → \frac{2}{5}). */
const STROKES = { x: [[10, 20, 30], [40, 50]], y: [[10, 12, 14], [20, 22]] };

describe("recognizeMath in the emulator (E1–E10)", () => {
  let owner = "";
  let stranger = "";

  before(async () => {
    owner = await signedInToken("owner-uid");
    stranger = await signedInToken("stranger-uid");
  });

  it("E1: no ID token → 401 UNAUTHENTICATED", async () => {
    assertError(await call({ v: 1, strokes: STROKES }), 401, "UNAUTHENTICATED");
  });

  it("E2: a signed-in user outside OWNER_UIDS → 403 PERMISSION_DENIED", async () => {
    assertError(await call({ v: 1, strokes: STROKES }, stranger), 403, "PERMISSION_DENIED");
  });

  it("E3: the owner without strokes or pngBase64 → 400 INVALID_ARGUMENT", async () => {
    assertError(await call({ v: 1 }, owner), 400, "INVALID_ARGUMENT");
  });

  it("E4: the owner with protocol version 2 → 400 INVALID_ARGUMENT", async () => {
    assertError(await call({ v: 2, engine: "fake", strokes: STROKES }, owner), 400, "INVALID_ARGUMENT");
  });

  it("E5: engine fake + 2 strokes of 5 points → \\frac{2}{5}, engine fake, engineVersion 1", async () => {
    const r = await call({ v: 1, engine: "fake", strokes: STROKES, locale: "ko" }, owner);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const result = r.body.result!;
    assert.equal(result.latex, "\\frac{2}{5}");
    assert.equal(result.engine, "fake");
    assert.equal(result.engineVersion, "1");
    assert.equal(result.confidence, 1);
    assert.deepEqual(result.alternatives, ["2/5"]);
    assert.equal(typeof result.ms, "number");
    assert.ok((result.ms as number) >= 0);
  });

  it("E6: a 67-byte PNG only → \\sqrt{67}", async () => {
    const r = await call({ v: 1, engine: "fake", pngBase64: PNG_67 }, owner);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.result!.latex, "\\sqrt{67}");
    assert.deepEqual(r.body.result!.alternatives, []);
  });

  it("E7: engine auto → the demo MATH_ENGINE (fake)", async () => {
    const r = await call({ v: 1, engine: "auto", strokes: STROKES }, owner);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.result!.latex, "\\frac{2}{5}");
    assert.equal(r.body.result!.engine, "fake");
    const byDefault = await call({ v: 1, strokes: STROKES }, owner);
    assert.equal(byDefault.body.result?.engine, "fake", "no engine means auto");
  });

  it("E8: engine gemini (no adapter) → 503 UNAVAILABLE", async () => {
    assertError(await call({ v: 1, engine: "gemini", strokes: STROKES }, owner), 503, "UNAVAILABLE");
  });

  it("E9: first point (-1, -1) → 503 UNAVAILABLE; (-2, -2) → 500 INTERNAL", async () => {
    const at = (p: number) => ({ x: [[p, 1, 2]], y: [[p, 1, 2]] });
    assertError(await call({ v: 1, engine: "fake", strokes: at(-1) }, owner), 503, "UNAVAILABLE");
    assertError(await call({ v: 1, engine: "fake", strokes: at(-2) }, owner), 500, "INTERNAL");
  });

  it("E10: pngBase64 of 2,097,153 characters → 400 INVALID_ARGUMENT", async () => {
    const big = PNG_67 + "A".repeat(2_097_153 - PNG_67.length);
    assert.equal(big.length, 2_097_153);
    assertError(await call({ v: 1, engine: "fake", pngBase64: big }, owner), 400, "INVALID_ARGUMENT");
  });
});
