// The math engine comparison tool (07-sync 6.9, S2-13): the five synthetic fixtures × the fake
// engine give a fixed summary.md, the normalisation table, no paid call without --confirm-cost
// or above --limit, key-less engines marked 'not configured', a time-out row from the injected
// AbortController, the Claude cost from response usage. No network: paid engines are counting
// stand-ins or the Claude adapter over a fake SDK client.

import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";

import { ClaudeEngine, type BetaMessage, type ClaudeMessagesClient } from "../../src/engines/claude.js";
import { EngineError, type EngineInput, type MathEngine } from "../../src/engines/engine.js";
import { FakeEngine } from "../../src/engines/fake.js";
import { ENGINE_TIMEOUT_MS } from "../../src/recognize_math.js";
import { normalizeLatex, renderSummaryMarkdown, summarize, type EvalRow } from "../eval_score.js";
import {
  CLAUDE_PRICE,
  DEFAULT_LIMIT,
  defaultEngine,
  loadFixtures,
  main,
  parseArgs,
  runEval,
  UsageError,
  type EvalDeps,
  type EvalOptions,
  type ToolEngineName,
} from "../math_eval.js";

// lib/tool/test → the source fixtures (not compiled).
const SYNTHETIC = join(__dirname, "..", "..", "..", "tool", "fixtures", "math", "synthetic");

function options(over: Partial<EvalOptions> = {}): EvalOptions {
  return { fixturesDir: SYNTHETIC, engines: ["fake"], limit: DEFAULT_LIMIT, confirmCost: false, ...over };
}

/** Deterministic deps: a clock that moves 1 ms per read, a signal that never fires. */
function deps(over: Partial<EvalDeps> = {}): EvalDeps & { lines: string[] } {
  let t = 0;
  const lines: string[] = [];
  return {
    env: {},
    now: () => ++t,
    engineSignal: () => new AbortController().signal,
    log: (line) => lines.push(line),
    lines,
    ...over,
  };
}

/** A paid-engine stand-in that counts its calls. */
function counting(name: "mathpix" | "claude", calls: { n: number }): MathEngine {
  return {
    name,
    accepts: { strokes: name === "mathpix", png: true },
    recognize: async () => {
      calls.n++;
      return { latex: "x", version: "stand-in" };
    },
  };
}

const FAKE_SUMMARY = [
  "# 수식 엔진 비교",
  "",
  "- 고정 자료 5개, 엔진 1개",
  "- 해석 성공 열은 비어 있다 — Dart 쪽 검사가 채운다(07-sync 6.9.3, Q5)",
  "- 지연은 엔진 호출 ms의 중앙값·p90(가장 가까운 순위), 비용은 도구 안 단가로 계산한 추정이다",
  "",
  "| 엔진 | 판 | 호출 | 정확 일치 | 정규화 일치 | 해석 성공 | 지연 중앙값 ms | 지연 p90 ms | 실패 | 비용 USD |",
  "|---|---|---|---|---|---|---|---|---|---|",
  "| fake | 1 | 5 | 2/5 (40%) | 3/5 (60%) |  | 2 | 2 | upstream 1 | 0.0000 |",
  "",
].join("\n");

describe("the synthetic fixtures × the fake engine", () => {
  it("are five, sorted by path, each well-formed", () => {
    const fixtures = loadFixtures(SYNTHETIC);
    assert.deepEqual(
      fixtures.map((f) => f.id),
      ["frac-01", "frac-02", "pow-01", "sqrt-01", "upstream-01"],
    );
    assert.ok(fixtures.every((f) => f.source === "synthetic"));
    assert.equal(fixtures.find((f) => f.id === "sqrt-01")!.png, "sqrt-01.png");
  });

  it("give exactly this summary.md and results.jsonl (deterministic)", async () => {
    const out = mkdtempSync(join(tmpdir(), "math-eval-"));
    const d = deps();
    const outcome = await runEval(options({ outDir: out }), d);
    assert.equal(outcome.status, "done");
    assert.equal(outcome.calls, 5);
    assert.equal(outcome.markdown, FAKE_SUMMARY);
    assert.equal(readFileSync(join(out, "summary.md"), "utf8"), FAKE_SUMMARY);
    const rows = readFileSync(join(out, "results.jsonl"), "utf8")
      .trimEnd()
      .split("\n")
      .map((l) => JSON.parse(l) as EvalRow);
    assert.deepEqual(rows, outcome.rows);
    assert.deepEqual(
      rows.map((r) => [r.fixtureId, r.engine, r.ok, r.latex ?? null, r.error ?? null]),
      [
        ["frac-01", "fake", true, "\\frac{2}{6}", null],
        ["frac-02", "fake", true, "\\frac{1}{4}", null],
        ["pow-01", "fake", true, "\\frac{3}{6}", null],
        ["sqrt-01", "fake", true, "\\sqrt{67}", null],
        ["upstream-01", "fake", false, null, "upstream"],
      ],
    );
    // The fake clock moves 1 ms per read; a thrown answer settles one read earlier.
    assert.deepEqual(rows.map((r) => r.ms), [2, 2, 2, 2, 1]);
    assert.deepEqual(rows.map((r) => r.costUsd ?? null), [0, 0, 0, 0, null]);
    assert.deepEqual(readdirSync(out).sort(), ["results.jsonl", "summary.md"]);
    assert.ok(d.lines.some((l) => l.includes("results.jsonl")));
  });

  it("main prints the table and exits 0 for fake only (no cost question)", async () => {
    const lines: string[] = [];
    let t = 0;
    const code = await main(["--fixtures", SYNTHETIC, "--engines", "fake", "--out", mkdtempSync(join(tmpdir(), "m-"))], {
      env: {},
      now: () => ++t,
      log: (l) => lines.push(l),
    });
    assert.equal(code, 0);
    assert.ok(lines.at(-1)!.includes("| fake | 1 | 5 |"));
  });
});

describe("normalizeLatex (6.9.3 table, 20 cases)", () => {
  for (const [input, normalized] of [
    ["\\frac{a}{b}", "\\frac{a}{b}"],
    [" \\frac { a } { b } ", "\\frac{a}{b}"],
    ["$x^2$", "x^2"],
    ["$$ x^2 $$", "x^2"],
    ["\\[x+1\\]", "x+1"],
    ["\\(x+1\\)", "x+1"],
    ["\\left( x \\right)", "(x)"],
    ["\\left[ x \\right]", "[x]"],
    ["\\dfrac{1}{2}", "\\frac{1}{2}"],
    ["\\tfrac{1}{2}", "\\frac{1}{2}"],
    ["x^{2}", "x^2"],
    ["a_{i}", "a_i"],
    ["x^{10}", "x^{10}"],
    ["x^{\\alpha}", "x^{\\alpha}"],
    ["a\\,b\\;c\\!d", "abcd"],
    ["a\\ b", "ab"],
    ["a\\quad b\\qquad c", "abc"],
    ["\\operatorname{sin} x", "\\sinx"],
    ["\\int_{0}^{1} f(x)\\,dx", "\\int_0^1f(x)dx"],
    ["\\sum_{k=1}^{n} k", "\\sum_{k=1}^nk"],
  ] as const) {
    it(`${JSON.stringify(input)} → ${JSON.stringify(normalized)}`, () => {
      assert.equal(normalizeLatex(input), normalized);
    });
  }
});

describe("summarize / renderSummaryMarkdown", () => {
  const row = (over: Partial<EvalRow>): EvalRow => ({
    fixtureId: "f",
    engine: "e",
    ok: true,
    latex: "x",
    expected: "x",
    ms: 10,
    ...over,
  });

  it("nearest-rank median and p90 over the calls only; failures by kind; cost summed", () => {
    const s = summarize([
      row({ fixtureId: "a", ms: 30, costUsd: 0.002, version: "v3" }),
      row({ fixtureId: "b", ms: 10, latex: "y", costUsd: 0.002, version: "v3" }),
      row({ fixtureId: "c", ok: false, latex: undefined, ms: 20, error: "timeout" }),
      row({ fixtureId: "d", ok: false, latex: undefined, ms: 0, error: "unsupportedInput" }),
      row({ fixtureId: "e", ok: false, latex: undefined, ms: 40, error: "badResponse" }),
      row({ fixtureId: "f", ok: false, latex: undefined, ms: 50, error: "timeout" }),
    ]);
    assert.equal(s.fixtures, 6);
    const e = s.engines[0]!;
    assert.equal(e.calls, 5);
    assert.equal(e.exact, 1);
    assert.equal(e.normalized, 1);
    assert.equal(e.medianMs, 30);
    assert.equal(e.p90Ms, 50);
    assert.deepEqual(e.failures, [
      ["badResponse", 1],
      ["timeout", 2],
      ["unsupportedInput", 1],
    ]);
    assert.equal(e.costUsd.toFixed(4), "0.0040");
    assert.deepEqual(e.versions, ["v3"]);
  });

  it("an engine whose rows are all notConfigured is one '설정 안 됨' line", () => {
    const md = renderSummaryMarkdown(
      summarize([row({ engine: "mathpix", ok: false, latex: undefined, ms: 0, error: "notConfigured" })]),
    );
    assert.ok(md.includes("| mathpix | — | 0 | 설정 안 됨 | 설정 안 됨 |  | — | — | — | — |"));
  });
});

describe("cost safety (6.9.2)", () => {
  const paid = (calls: { n: number }) => (name: ToolEngineName) =>
    name === "fake" ? new FakeEngine() : counting(name, calls);

  it("a paid engine without --confirm-cost: the estimate, then no call at all", async () => {
    const calls = { n: 0 };
    let fakeCalls = 0;
    const d = deps({
      makeEngine: (name) => {
        if (name !== "fake") return counting(name, calls);
        const f = new FakeEngine();
        return { ...f, name: f.name, accepts: f.accepts, recognize: async (i: EngineInput, s: AbortSignal) => (fakeCalls++, f.recognize(i, s)) };
      },
    });
    const outcome = await runEval(options({ engines: ["fake", "mathpix", "claude"] }), d);
    assert.equal(outcome.status, "needsConfirm");
    assert.equal(outcome.calls, 0);
    assert.equal(calls.n, 0);
    assert.equal(fakeCalls, 0, "nothing runs, the free engine neither");
    assert.deepEqual(outcome.estimate.calls, { mathpix: 5, claude: 1 });
    const claudeEach = (1500 * CLAUDE_PRICE.inputPerMTok + 1000 * CLAUDE_PRICE.outputPerMTok) / 1e6;
    assert.equal(outcome.estimate.usd.toFixed(6), (5 * 0.002 + claudeEach).toFixed(6));
    assert.match(d.lines[0]!, /^paid calls: mathpix 5 × \$0\.0020, claude 1 × \$0\.0260 — at most about \$0\.0360$/);
    assert.match(d.lines[1]!, /--confirm-cost/);

    const code = await main(["--fixtures", SYNTHETIC, "--engines", "mathpix"], {
      env: {},
      log: () => {},
      makeEngine: paid(calls),
    });
    assert.equal(code, 2);
    assert.equal(calls.n, 0);
  });

  it("with --confirm-cost the paid calls run (two at a time, rows in fixture order)", async () => {
    const calls = { n: 0 };
    let running = 0;
    let most = 0;
    const slow: MathEngine = {
      name: "mathpix",
      accepts: { strokes: true, png: true },
      recognize: async () => {
        calls.n++;
        running++;
        most = Math.max(most, running);
        await new Promise((r) => setImmediate(r));
        running--;
        return { latex: "x", version: "v3" };
      },
    };
    const outcome = await runEval(
      options({ engines: ["mathpix"], confirmCost: true }),
      deps({ makeEngine: () => slow }),
    );
    assert.equal(outcome.status, "done");
    assert.equal(calls.n, 5);
    assert.equal(most, 2);
    assert.deepEqual(
      outcome.rows.map((r) => r.fixtureId),
      ["frac-01", "frac-02", "pow-01", "sqrt-01", "upstream-01"],
    );
    assert.ok(outcome.rows.every((r) => r.costUsd === 0.002));
  });

  it("more paid calls than --limit: nothing called even with --confirm-cost", async () => {
    const calls = { n: 0 };
    const d = deps({ makeEngine: paid(calls) });
    const outcome = await runEval(options({ engines: ["mathpix"], confirmCost: true, limit: 4 }), d);
    assert.equal(outcome.status, "overLimit");
    assert.equal(outcome.calls, 0);
    assert.equal(calls.n, 0);
    assert.match(d.lines.at(-1)!, /more than --limit 4/);
  });
});

describe("engines from developer environment variables (6.9)", () => {
  it("no key → every row of that engine notConfigured, no cost question, '설정 안 됨'", async () => {
    const d = deps({ env: { MATHPIX_APP_ID: "app-only" } });
    const outcome = await runEval(options({ engines: ["fake", "mathpix", "claude"] }), d);
    assert.equal(outcome.status, "done");
    assert.equal(outcome.calls, 5, "the fake engine only");
    for (const name of ["mathpix", "claude"]) {
      const rows = outcome.rows.filter((r) => r.engine === name);
      assert.equal(rows.length, 5);
      assert.ok(rows.every((r) => !r.ok && r.error === "notConfigured" && r.ms === 0));
      assert.ok(outcome.markdown!.includes(`| ${name} | — | 0 | 설정 안 됨 | 설정 안 됨 |`));
    }
  });

  it("defaultEngine: keys and --claude-model are needed; values never reach the log", async () => {
    const opts = options();
    assert.ok(defaultEngine("fake", {}, opts) instanceof FakeEngine);
    assert.ok(defaultEngine("mathpix", { MATHPIX_APP_ID: "a" }, opts) instanceof EngineError);
    assert.equal((defaultEngine("mathpix", { MATHPIX_APP_ID: "a", MATHPIX_APP_KEY: "k" }, opts) as MathEngine).name, "mathpix");
    const noModel = defaultEngine("claude", { ANTHROPIC_API_KEY: "secret-key-1" }, opts);
    assert.ok(noModel instanceof EngineError && noModel.kind === "notConfigured");
    const claude = defaultEngine("claude", { ANTHROPIC_API_KEY: "secret-key-1" }, { ...opts, claudeModel: "m" });
    assert.ok(claude instanceof ClaudeEngine);

    const lines: string[] = [];
    const env = { MATHPIX_APP_ID: "secret-app-2", MATHPIX_APP_KEY: "secret-key-3" };
    const code = await main(["--fixtures", SYNTHETIC, "--engines", "mathpix"], { env, log: (l) => lines.push(l) });
    assert.equal(code, 2, "paid and not confirmed");
    for (const secret of Object.values(env)) {
      assert.ok(lines.every((l) => !l.includes(secret)));
    }
  });

  it("Claude through the adapter: PNG fixtures only, version = the answering model, cost from usage", async () => {
    const client: ClaudeMessagesClient = {
      create: async () =>
        ({
          id: "msg_1",
          type: "message",
          role: "assistant",
          model: "answering-model",
          content: [{ type: "text", text: JSON.stringify({ latex: "\\sqrt{67}", confidence: 0.9, alternatives: [] }) }],
          stop_reason: "end_turn",
          stop_sequence: null,
          usage: { input_tokens: 1000, output_tokens: 500, iterations: null },
        }) as unknown as BetaMessage,
    };
    const outcome = await runEval(
      options({ engines: ["claude"], confirmCost: true, claudePrice: { inputPerMTok: 2, outputPerMTok: 10 } }),
      deps({ makeEngine: () => new ClaudeEngine({ apiKey: "k", model: "requested-model", client }) }),
    );
    assert.equal(outcome.status, "done");
    assert.equal(outcome.calls, 1);
    const png = outcome.rows.find((r) => r.fixtureId === "sqrt-01")!;
    assert.equal(png.ok, true);
    assert.equal(png.version, "answering-model");
    assert.equal(png.costUsd, (1000 * 2 + 500 * 10) / 1e6);
    assert.ok(
      outcome.rows.filter((r) => r.fixtureId !== "sqrt-01").every((r) => r.error === "unsupportedInput" && r.ms === 0),
    );
    assert.ok(outcome.markdown!.includes("| claude | answering-model | 1 | 1/5 (20%) | 1/5 (20%) |"));
  });
});

describe("time-outs and errors", () => {
  it("the per-call signal (ENGINE_TIMEOUT_MS) aborted → a 'timeout' row; the run goes on", async () => {
    const controller = new AbortController();
    const asked: number[] = [];
    let started = 0;
    const waits: MathEngine = {
      name: "mathpix",
      accepts: { strokes: true, png: true },
      recognize: (_input, signal) => {
        started++;
        if (started === 1) {
          // The first call waits for its signal, which the test aborts.
          return new Promise((_, reject) => {
            signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
            setImmediate(() => controller.abort());
          });
        }
        return Promise.resolve({ latex: "x", version: "v3" });
      },
    };
    const outcome = await runEval(
      options({ engines: ["mathpix"], confirmCost: true }),
      deps({
        makeEngine: () => waits,
        engineSignal: (ms) => {
          asked.push(ms);
          return asked.length === 1 ? controller.signal : new AbortController().signal;
        },
      }),
    );
    assert.deepEqual(asked, [ENGINE_TIMEOUT_MS, ENGINE_TIMEOUT_MS, ENGINE_TIMEOUT_MS, ENGINE_TIMEOUT_MS, ENGINE_TIMEOUT_MS]);
    assert.equal(outcome.rows[0]!.error, "timeout");
    assert.equal(outcome.rows[0]!.ok, false);
    assert.ok(outcome.rows.slice(1).every((r) => r.ok));
    assert.ok(outcome.markdown!.includes("timeout 1"));
  });

  it("an EngineError keeps its kind; another error without abort is upstream", async () => {
    let i = 0;
    const flaky: MathEngine = {
      name: "mathpix",
      accepts: { strokes: true, png: true },
      recognize: async () => {
        i++;
        if (i === 1) throw new EngineError("rateLimited", "429");
        if (i === 2) throw new TypeError("fetch failed");
        return { latex: "x", version: "v3" };
      },
    };
    const outcome = await runEval(
      options({ engines: ["mathpix"], confirmCost: true, concurrency: 1 }),
      deps({ makeEngine: () => flaky }),
    );
    assert.deepEqual(
      outcome.rows.map((r) => r.error ?? null),
      ["rateLimited", "upstream", null, null, null],
    );
  });
});

describe("parseArgs", () => {
  it("defaults: fake only, limit 60, no cost confirmation, eval-out/<date>", () => {
    assert.deepEqual(parseArgs([], "2026-11-06"), {
      fixturesDir: "tool/fixtures/math",
      engines: ["fake"],
      limit: 60,
      confirmCost: false,
      outDir: join("eval-out", "2026-11-06"),
    });
  });

  it("every flag", () => {
    const o = parseArgs(
      [
        "--fixtures", "f", "--engines", "fake,mathpix,claude", "--claude-model", "m",
        "--claude-price", "1,5", "--limit", "100", "--confirm-cost", "--out", "o",
      ],
      "d",
    );
    assert.deepEqual(o, {
      fixturesDir: "f",
      engines: ["fake", "mathpix", "claude"],
      claudeModel: "m",
      claudePrice: { inputPerMTok: 1, outputPerMTok: 5 },
      limit: 100,
      confirmCost: true,
      outDir: "o",
    });
  });

  for (const argv of [
    ["--engines", "gemini"],
    ["--engines", ""],
    ["--limit", "-1"],
    ["--limit", "1.5"],
    ["--claude-model"],
    ["--claude-price", "x"],
    ["--what"],
  ]) {
    it(`${JSON.stringify(argv)} → UsageError`, () => {
      assert.throws(() => parseArgs(argv, "d"), UsageError);
    });
  }

  it("main: a usage error is exit code 2 with a message", async () => {
    const lines: string[] = [];
    assert.equal(await main(["--engines", "nope"], { log: (l) => lines.push(l) }), 2);
    assert.match(lines[0]!, /^math_eval: unknown engine 'nope'/);
  });
});

describe("sources (6.9 — adapters from env vars, not Firebase params)", () => {
  it("the tool files do not import src/params", () => {
    const root = join(__dirname, "..", "..", "..", "tool");
    for (const file of ["math_eval.ts", "eval_score.ts"]) {
      const text = readFileSync(join(root, file), "utf8");
      assert.doesNotMatch(text, /from\s+["'][^"']*params(\.js)?["']/, file);
    }
  });
});
