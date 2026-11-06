// The math engine comparison tool (docs/plans/m5-7/07-sync.md 6.9, PLAN F-14): fixtures (strokes
// JSON + expected LaTeX) → each engine adapter → results.jsonl + summary.md. A developer tool:
// it calls the adapters of src/engines directly (not the callable) and builds them from the
// developer's environment variables — never from Firebase params (src/params.ts).
//
//   npm run eval:math -- --fixtures tool/fixtures/math --engines fake,mathpix,claude
//                        [--claude-model <model — required for claude, no default>]
//                        [--limit 60] [--confirm-cost] [--out eval-out/<date>]
//
// Safety (6.9.2): keys only from MATHPIX_APP_ID / MATHPIX_APP_KEY / ANTHROPIC_API_KEY and never
// written to a file or the log; with any paid engine the run shows the largest cost estimate and
// makes NO call without --confirm-cost; never more than --limit paid calls; two calls at a time,
// each under the server's ENGINE_TIMEOUT_MS signal; an engine error fails its row only.

import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";

import { ClaudeEngine } from "../src/engines/claude.js";
import { EngineError, type EngineInput, type MathEngine } from "../src/engines/engine.js";
import { FakeEngine } from "../src/engines/fake.js";
import { MathpixEngine } from "../src/engines/mathpix.js";
import type { Locale, StrokesInput } from "../src/protocol.js";
import { ENGINE_TIMEOUT_MS } from "../src/recognize_math.js";
import { type EvalRow, renderSummaryMarkdown, summarize, type EvalSummary } from "./eval_score.js";

export const ENGINE_NAMES = ["fake", "mathpix", "claude"] as const;
export type ToolEngineName = (typeof ENGINE_NAMES)[number];

/** Mathpix, per request (07-sync 6.8.12 / research 03 6.1 — [guess], price list not read). */
export const MATHPIX_USD_PER_CALL = 0.002;

/** Claude, USD per million tokens of the model assumed when 07-sync 6.8.12 was written (research
 *  03 6.4, model table of 2026-10-06). The model itself is the --claude-model argument; pass
 *  --claude-price <in>,<out> for another one. */
export const CLAUDE_PRICE: Readonly<{ inputPerMTok: number; outputPerMTok: number; asOf: string }> = {
  inputPerMTok: 4,
  outputPerMTok: 20,
  asOf: "2026-10-06",
};

/** Largest tokens of one formula call for the estimate before the run (07-sync 6.8.12). */
export const CLAUDE_ESTIMATE_TOKENS = { input: 1500, output: 1000 } as const;

export const DEFAULT_LIMIT = 60;
export const CONCURRENCY = 2;

/** One fixture file (6.9.1). */
export interface MathFixture {
  id: string;
  tags: string[];
  expected: string;
  strokes?: StrokesInput;
  /** File name next to the fixture file. */
  png?: string;
  source: string;
  locale?: Locale;
  /** Where it was read from (not in the file). */
  path: string;
}

export interface EvalOptions {
  fixturesDir: string;
  engines: ToolEngineName[];
  claudeModel?: string;
  claudePrice?: { inputPerMTok: number; outputPerMTok: number };
  limit: number;
  confirmCost: boolean;
  /** undefined → nothing is written (tests). */
  outDir?: string;
  concurrency?: number;
}

export interface EvalDeps {
  env: Readonly<Record<string, string | undefined>>;
  /** Milliseconds, for the per-call latency. */
  now: () => number;
  /** The per-call signal (the server's engineSignal — default AbortSignal.timeout). */
  engineSignal: (ms: number) => AbortSignal;
  log: (line: string) => void;
  /** Test seam: builds the adapter of [name] (default: the real adapters from [env]). */
  makeEngine?: (name: ToolEngineName, env: EvalDeps["env"], opts: EvalOptions) => MathEngine | EngineError;
}

export interface CostEstimate {
  /** Paid engine → planned calls (configured engines only). */
  calls: Partial<Record<ToolEngineName, number>>;
  usd: number;
}

export interface EvalOutcome {
  status: "done" | "needsConfirm" | "overLimit";
  /** Engine calls made (all engines). */
  calls: number;
  estimate: CostEstimate;
  rows: EvalRow[];
  summary?: EvalSummary;
  markdown?: string;
}

export class UsageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "UsageError";
  }
}

// ---- arguments ---------------------------------------------------------------------------------

export function parseArgs(argv: readonly string[], today: string): EvalOptions {
  const opts: EvalOptions = {
    fixturesDir: "tool/fixtures/math",
    engines: ["fake"],
    limit: DEFAULT_LIMIT,
    confirmCost: false,
    outDir: join("eval-out", today),
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    const value = (): string => {
      const v = argv[++i];
      if (v === undefined || v.startsWith("--")) throw new UsageError(`${arg} needs a value`);
      return v;
    };
    switch (arg) {
      case "--fixtures":
        opts.fixturesDir = value();
        break;
      case "--engines": {
        const names = value().split(",").map((s) => s.trim()).filter((s) => s.length > 0);
        for (const n of names) {
          if (!(ENGINE_NAMES as readonly string[]).includes(n)) {
            throw new UsageError(`unknown engine '${n}' (one of ${ENGINE_NAMES.join(", ")})`);
          }
        }
        if (names.length === 0) throw new UsageError("--engines is empty");
        opts.engines = [...new Set(names)] as ToolEngineName[];
        break;
      }
      case "--claude-model":
        opts.claudeModel = value();
        break;
      case "--claude-price": {
        const [i0, o0] = value().split(",").map(Number);
        if (!(i0! >= 0) || !(o0! >= 0)) throw new UsageError("--claude-price is <in>,<out> USD per MTok");
        opts.claudePrice = { inputPerMTok: i0!, outputPerMTok: o0! };
        break;
      }
      case "--limit": {
        const n = Number(value());
        if (!Number.isInteger(n) || n < 0) throw new UsageError("--limit is a whole number ≥ 0");
        opts.limit = n;
        break;
      }
      case "--confirm-cost":
        opts.confirmCost = true;
        break;
      case "--out":
        opts.outDir = value();
        break;
      default:
        throw new UsageError(`unknown argument '${arg}'`);
    }
  }
  return opts;
}

// ---- fixtures ----------------------------------------------------------------------------------

function jsonFiles(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir).sort()) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) out.push(...jsonFiles(path));
    else if (name.endsWith(".json")) out.push(path);
  }
  return out;
}

function isNumberGrid(v: unknown): v is number[][] {
  return Array.isArray(v) && v.every((s) => Array.isArray(s) && s.every((n) => typeof n === "number"));
}

/** Every *.json under [dir] (sorted by path); UsageError for a malformed one or a repeated id. */
export function loadFixtures(dir: string): MathFixture[] {
  const fixtures: MathFixture[] = [];
  const ids = new Set<string>();
  for (const path of jsonFiles(dir)) {
    const where = relative(dir, path);
    let raw: unknown;
    try {
      raw = JSON.parse(readFileSync(path, "utf8"));
    } catch (e) {
      throw new UsageError(`${where}: not JSON (${(e as Error).message})`);
    }
    const f = raw as Record<string, unknown>;
    if (typeof f !== "object" || f === null || typeof f.id !== "string" || f.id.length === 0) {
      throw new UsageError(`${where}: needs a string id`);
    }
    if (typeof f.expected !== "string") throw new UsageError(`${where}: needs a string expected`);
    if (typeof f.source !== "string") throw new UsageError(`${where}: needs a string source`);
    if (!Array.isArray(f.tags) || !f.tags.every((t) => typeof t === "string")) {
      throw new UsageError(`${where}: tags must be a list of strings`);
    }
    let strokes: StrokesInput | undefined;
    if (f.strokes !== undefined) {
      const s = f.strokes as Record<string, unknown>;
      if (!isNumberGrid(s.x) || !isNumberGrid(s.y) || (s.t !== undefined && !isNumberGrid(s.t))) {
        throw new UsageError(`${where}: strokes is {x, y, t?} of number lists`);
      }
      strokes = { x: s.x, y: s.y, ...(s.t === undefined ? {} : { t: s.t as number[][] }) };
    }
    if (f.png !== undefined && typeof f.png !== "string") throw new UsageError(`${where}: png is a file name`);
    if (strokes === undefined && f.png === undefined) throw new UsageError(`${where}: needs strokes or png`);
    if (f.locale !== undefined && f.locale !== "ko" && f.locale !== "en") {
      throw new UsageError(`${where}: locale is 'ko' or 'en'`);
    }
    if (ids.has(f.id)) throw new UsageError(`${where}: id '${f.id}' repeats`);
    ids.add(f.id);
    fixtures.push({
      id: f.id,
      tags: f.tags as string[],
      expected: f.expected,
      ...(strokes === undefined ? {} : { strokes }),
      ...(f.png === undefined ? {} : { png: f.png as string }),
      source: f.source,
      ...(f.locale === undefined ? {} : { locale: f.locale as Locale }),
      path,
    });
  }
  return fixtures;
}

// ---- engines -----------------------------------------------------------------------------------

/** The real adapters, from developer environment variables only (6.9). */
export function defaultEngine(
  name: ToolEngineName,
  env: EvalDeps["env"],
  opts: EvalOptions,
): MathEngine | EngineError {
  switch (name) {
    case "fake":
      return new FakeEngine();
    case "mathpix": {
      const appId = env.MATHPIX_APP_ID ?? "";
      const apiKey = env.MATHPIX_APP_KEY ?? "";
      if (appId === "" || apiKey === "") {
        return new EngineError("notConfigured", "mathpix: MATHPIX_APP_ID and MATHPIX_APP_KEY are needed");
      }
      return new MathpixEngine({ appId, apiKey });
    }
    case "claude": {
      const apiKey = env.ANTHROPIC_API_KEY ?? "";
      const model = opts.claudeModel ?? "";
      if (apiKey === "" || model === "") {
        return new EngineError("notConfigured", "claude: ANTHROPIC_API_KEY and --claude-model are needed");
      }
      return new ClaudeEngine({ apiKey, model });
    }
  }
}

const PAID: ReadonlySet<ToolEngineName> = new Set(["mathpix", "claude"]);

function inputFor(engine: MathEngine, f: MathFixture): EngineInput | null {
  const strokes = engine.accepts.strokes ? f.strokes : undefined;
  const png = engine.accepts.png && f.png !== undefined ? readFileSync(join(dirname(f.path), f.png)) : undefined;
  if (strokes === undefined && png === undefined) return null;
  return {
    locale: f.locale ?? "ko",
    ...(strokes === undefined ? {} : { strokes }),
    ...(png === undefined ? {} : { png }),
  };
}

function costOf(
  name: string,
  logInfo: Record<string, string | number | boolean> | undefined,
  price: { inputPerMTok: number; outputPerMTok: number },
): number {
  if (name === "mathpix") return MATHPIX_USD_PER_CALL;
  if (name === "claude") {
    const inTok = typeof logInfo?.inTok === "number" ? logInfo.inTok : 0;
    const outTok = typeof logInfo?.outTok === "number" ? logInfo.outTok : 0;
    return (inTok * price.inputPerMTok + outTok * price.outputPerMTok) / 1e6;
  }
  return 0;
}

function estimatePerCall(name: ToolEngineName, price: { inputPerMTok: number; outputPerMTok: number }): number {
  if (name === "mathpix") return MATHPIX_USD_PER_CALL;
  if (name === "claude") {
    return (
      (CLAUDE_ESTIMATE_TOKENS.input * price.inputPerMTok + CLAUDE_ESTIMATE_TOKENS.output * price.outputPerMTok) / 1e6
    );
  }
  return 0;
}

// ---- the run -----------------------------------------------------------------------------------

interface Job {
  index: number;
  fixture: MathFixture;
  name: ToolEngineName;
  engine: MathEngine;
  input: EngineInput;
}

async function callOne(job: Job, deps: EvalDeps, price: { inputPerMTok: number; outputPerMTok: number }): Promise<EvalRow> {
  const { fixture, name, engine, input } = job;
  const signal = deps.engineSignal(ENGINE_TIMEOUT_MS);
  const started = deps.now();
  try {
    const out = await engine.recognize(input, signal);
    return {
      fixtureId: fixture.id,
      engine: name,
      ok: true,
      latex: out.latex,
      expected: fixture.expected,
      ms: deps.now() - started,
      costUsd: costOf(name, out.logInfo, price),
      version: out.version,
    };
  } catch (e) {
    const kind = e instanceof EngineError ? e.kind : signal.aborted ? "timeout" : "upstream";
    return {
      fixtureId: fixture.id,
      engine: name,
      ok: false,
      expected: fixture.expected,
      ms: deps.now() - started,
      error: kind,
    };
  }
}

/** Runs the comparison; writes results.jsonl and summary.md under opts.outDir when set. */
export async function runEval(opts: EvalOptions, deps: EvalDeps): Promise<EvalOutcome> {
  const fixtures = loadFixtures(opts.fixturesDir);
  const price = opts.claudePrice ?? CLAUDE_PRICE;
  const make = deps.makeEngine ?? defaultEngine;
  const engines = opts.engines.map((name) => ({ name, engine: make(name, deps.env, opts) }));

  // Every fixture × engine, in that order: a row now (not configured / unusable input) or a job.
  const slots: (EvalRow | Job)[] = [];
  const estimate: CostEstimate = { calls: {}, usd: 0 };
  for (const fixture of fixtures) {
    for (const { name, engine } of engines) {
      const index = slots.length;
      if (engine instanceof EngineError) {
        slots.push({ fixtureId: fixture.id, engine: name, ok: false, expected: fixture.expected, ms: 0, error: engine.kind });
        continue;
      }
      const input = inputFor(engine, fixture);
      if (input === null) {
        slots.push({ fixtureId: fixture.id, engine: name, ok: false, expected: fixture.expected, ms: 0, error: "unsupportedInput" });
        continue;
      }
      if (PAID.has(name)) {
        estimate.calls[name] = (estimate.calls[name] ?? 0) + 1;
        estimate.usd += estimatePerCall(name, price);
      }
      slots.push({ index, fixture, name, engine, input });
    }
  }

  const paidCalls = Object.values(estimate.calls).reduce((a, b) => a + b, 0);
  if (paidCalls > 0) {
    const parts = Object.entries(estimate.calls).map(
      ([name, n]) => `${name} ${n} × $${estimatePerCall(name as ToolEngineName, price).toFixed(4)}`,
    );
    deps.log(`paid calls: ${parts.join(", ")} — at most about $${estimate.usd.toFixed(4)}`);
  }
  if (paidCalls > opts.limit) {
    deps.log(`${paidCalls} paid calls is more than --limit ${opts.limit}: nothing called`);
    return { status: "overLimit", calls: 0, estimate, rows: [] };
  }
  if (paidCalls > 0 && !opts.confirmCost) {
    deps.log("add --confirm-cost to make these calls: nothing called");
    return { status: "needsConfirm", calls: 0, estimate, rows: [] };
  }

  const jobs = slots.filter((s): s is Job => "input" in s);
  const results = new Map<number, EvalRow>();
  let next = 0;
  const worker = async (): Promise<void> => {
    while (next < jobs.length) {
      const job = jobs[next++]!;
      results.set(job.index, await callOne(job, deps, price));
    }
  };
  const width = Math.max(1, Math.min(opts.concurrency ?? CONCURRENCY, jobs.length));
  await Promise.all(Array.from({ length: width }, worker));

  const rows = slots.map((s, i) => ("input" in s ? results.get(i)! : s));
  const summary = summarize(rows);
  const markdown = renderSummaryMarkdown(summary);
  if (opts.outDir !== undefined) {
    mkdirSync(opts.outDir, { recursive: true });
    writeFileSync(join(opts.outDir, "results.jsonl"), rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
    writeFileSync(join(opts.outDir, "summary.md"), markdown);
    deps.log(`wrote ${join(opts.outDir, "results.jsonl")} and summary.md`);
  }
  return { status: "done", calls: jobs.length, estimate, rows, summary, markdown };
}

/** The command line; returns the exit code (0 done, 2 usage / not confirmed / over the limit). */
export async function main(argv: readonly string[], deps?: Partial<EvalDeps>): Promise<number> {
  const log = deps?.log ?? ((line: string) => console.log(line));
  try {
    const opts = parseArgs(argv, new Date().toISOString().slice(0, 10));
    const outcome = await runEval(opts, {
      env: deps?.env ?? process.env,
      now: deps?.now ?? (() => performance.now()),
      engineSignal: deps?.engineSignal ?? ((ms) => AbortSignal.timeout(ms)),
      log,
      ...(deps?.makeEngine === undefined ? {} : { makeEngine: deps.makeEngine }),
    });
    if (outcome.status !== "done") return 2;
    log(outcome.markdown!.trimEnd());
    return 0;
  } catch (e) {
    if (e instanceof UsageError) {
      log(`math_eval: ${e.message}`);
      return 2;
    }
    throw e;
  }
}

if (require.main === module) {
  void main(process.argv.slice(2)).then((code) => {
    process.exitCode = code;
  });
}
