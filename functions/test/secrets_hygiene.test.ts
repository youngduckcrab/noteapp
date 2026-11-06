// A light safety net (docs/plans/m5-7/07-sync.md 6.8.9, F-1): no committed file under functions/
// carries a key-shaped string — an Anthropic key (sk-ant-…), a Mathpix app key (app_key=…), or a
// MATH_API_KEY value — and no committed .env* file names MATH_API_KEY at all (the key lives in
// Secret Manager; .secret.local / .env.local are ignored by git). The walk skips what
// .gitignore leaves out of functions/ (node_modules, lib, eval-out, .env.local, .secret.local,
// firebase-debug*.log) so it also runs on an exported tree without git.

import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, it } from "node:test";

/** functions/ (this file runs as lib/test/secrets_hygiene.test.js). */
const ROOT = join(__dirname, "..", "..");
const IGNORED_DIRS = new Set(["node_modules", "lib", "eval-out", ".git"]);
const IGNORED_FILES = new Set([".env.local", ".secret.local"]);

function committedFiles(dir: string = ROOT): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      if (!IGNORED_DIRS.has(name)) out.push(...committedFiles(path));
    } else if (!IGNORED_FILES.has(name) && !/^firebase-debug.*\.log$/.test(name)) {
      out.push(path);
    }
  }
  return out.sort();
}

/** Key-shaped text: [name, pattern]. Built so that this file's own source does not match. */
const KEY_PATTERNS: ReadonlyArray<readonly [string, RegExp]> = [
  ["Anthropic key", new RegExp("sk-" + "ant-[A-Za-z0-9_-]{8,}")],
  ["Mathpix app key", new RegExp("app" + "_key\\s*[=:]\\s*[\"']?[A-Za-z0-9_-]{8,}")],
  ["MATH_API_KEY value", new RegExp("MATH_API" + "_KEY\\s*[=:]\\s*[\"'][^\"']+[\"']")],
];
const ENV_KEY_LINE = new RegExp("^\\s*MATH_API" + "_KEY\\s*=", "m");

function findings(text: string, isEnvFile: boolean): string[] {
  const found = KEY_PATTERNS.filter(([, pattern]) => pattern.test(text)).map(([name]) => name);
  if (isEnvFile && ENV_KEY_LINE.test(text)) found.push("MATH_API_KEY line in an .env file");
  return found;
}

describe("secrets hygiene (F-1)", () => {
  it("the walk sees the committed sources, tests and .env files and skips build output", () => {
    const files = committedFiles().map((f) => relative(ROOT, f));
    for (const expected of ["package.json", "src/params.ts", "test/secrets_hygiene.test.ts", ".env.demo-noteapp"]) {
      assert.ok(files.includes(expected), `${expected} in ${files.join(", ")}`);
    }
    assert.ok(!files.some((f) => f.startsWith("node_modules/") || f.startsWith("lib/")));
    assert.ok(!files.includes(".env.local") && !files.includes(".secret.local"));
  });

  it("no committed file under functions/ has a key-shaped string", () => {
    const bad: string[] = [];
    for (const file of committedFiles()) {
      const name = relative(ROOT, file);
      const found = findings(readFileSync(file, "utf8"), /(^|\/)\.env/.test(name));
      if (found.length > 0) bad.push(`${name}: ${found.join(", ")}`);
    }
    assert.deepEqual(bad, []);
  });

  it("the patterns catch planted keys (and not the parameter definitions)", () => {
    const anthropic = "sk-" + "ant-" + "api03-abcdefghijklmnop";
    const mathpix = "app" + "_key=" + "0123456789abcdef";
    const quoted = "MATH_API" + '_KEY = "' + "0123456789abcdef" + '"';
    assert.deepEqual(findings(`const k = "${anthropic}";`, false), ["Anthropic key"]);
    assert.deepEqual(findings(`headers: { ${mathpix} }`, false), ["Mathpix app key"]);
    assert.deepEqual(findings(quoted, false), ["MATH_API_KEY value"]);
    assert.deepEqual(findings("MATH_API" + "_KEY=unset\n", true), ["MATH_API_KEY line in an .env file"]);
    assert.deepEqual(findings('export const MATH_API_KEY = defineSecret("MATH_API_KEY");', false), []);
    assert.deepEqual(findings("firebase functions:secrets:set MATH_API_KEY", false), []);
    assert.deepEqual(findings("OWNER_UIDS=owner-uid\nMATH_ENGINE=fake\n", true), []);
  });
});
