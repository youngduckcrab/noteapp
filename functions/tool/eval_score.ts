// Scoring and the summary table of the math engine comparison tool (docs/plans/m5-7/07-sync.md
// 4.5 'tool/eval_score.ts', 6.9.3, 6.9.4). Pure functions — the tool's tests check them with
// fixed strings. normalizeLatex is the server's own (src/engines/latex.ts), re-exported so the
// tool and the callable read an answer the same way.

import { normalizeLatex } from "../src/engines/latex.js";

export { normalizeLatex };

/** One fixture × engine (results.jsonl line, 6.9.4). */
export interface EvalRow {
  fixtureId: string;
  engine: string;
  ok: boolean;
  latex?: string;
  expected: string;
  /** Engine call time; 0 when no call was made (not configured, input the engine cannot take). */
  ms: number;
  /** EngineErrorKind (6.8.8) when ok is false. */
  error?: string;
  costUsd?: number;
  /** EngineOutput.version — the engine / model that actually answered (6.9). */
  version?: string;
}

/** Errors for which the engine was not called (no latency, no cost). */
export const NOT_CALLED: ReadonlySet<string> = new Set(["notConfigured", "unsupportedInput"]);

export interface EngineSummary {
  engine: string;
  /** false when every row of the engine is notConfigured (no key / no model). */
  configured: boolean;
  rows: number;
  calls: number;
  exact: number;
  normalized: number;
  /** Nearest-rank median / p90 of the calls' ms; null without calls. */
  medianMs: number | null;
  p90Ms: number | null;
  /** Error kind → rows, sorted by kind (notConfigured left out). */
  failures: [string, number][];
  costUsd: number;
  /** Distinct versions that answered, sorted. */
  versions: string[];
}

export interface EvalSummary {
  fixtures: number;
  engines: EngineSummary[];
}

/** 6.9.3 '정확 일치'. */
export function exactMatch(latex: string | undefined, expected: string): boolean {
  return latex !== undefined && latex.trim() === expected.trim();
}

/** 6.9.3 '정규화 일치'. */
export function normalizedMatch(latex: string | undefined, expected: string): boolean {
  return latex !== undefined && normalizeLatex(latex) === normalizeLatex(expected);
}

/** Nearest rank: the smallest value with at least q of the values at or below it. */
function rank(sorted: number[], q: number): number | null {
  if (sorted.length === 0) return null;
  return sorted[Math.max(0, Math.ceil(q * sorted.length) - 1)]!;
}

/** Per engine, in the order the engines first appear in [rows]. */
export function summarize(rows: EvalRow[]): EvalSummary {
  const order: string[] = [];
  const byEngine = new Map<string, EvalRow[]>();
  for (const row of rows) {
    let list = byEngine.get(row.engine);
    if (list === undefined) {
      list = [];
      byEngine.set(row.engine, list);
      order.push(row.engine);
    }
    list.push(row);
  }
  const engines = order.map((engine): EngineSummary => {
    const list = byEngine.get(engine)!;
    const called = list.filter((r) => r.error === undefined || !NOT_CALLED.has(r.error));
    const ms = called.map((r) => r.ms).sort((a, b) => a - b);
    const failures = new Map<string, number>();
    for (const r of list) {
      if (r.ok || r.error === undefined || r.error === "notConfigured") continue;
      failures.set(r.error, (failures.get(r.error) ?? 0) + 1);
    }
    return {
      engine,
      configured: !list.every((r) => r.error === "notConfigured"),
      rows: list.length,
      calls: called.length,
      exact: list.filter((r) => r.ok && exactMatch(r.latex, r.expected)).length,
      normalized: list.filter((r) => r.ok && normalizedMatch(r.latex, r.expected)).length,
      medianMs: rank(ms, 0.5),
      p90Ms: rank(ms, 0.9),
      failures: [...failures.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)),
      costUsd: list.reduce((sum, r) => sum + (r.costUsd ?? 0), 0),
      versions: [...new Set(called.flatMap((r) => (r.version === undefined ? [] : [r.version])))].sort(),
    };
  });
  return { fixtures: new Set(rows.map((r) => r.fixtureId)).size, engines };
}

function ratio(n: number, d: number): string {
  return d === 0 ? "—" : `${n}/${d} (${Math.round((100 * n) / d)}%)`;
}

/** The comparison table (research 03 6.6 → 07-sync 6.9.3 columns), as summary.md. */
export function renderSummaryMarkdown(s: EvalSummary): string {
  const lines = [
    "# 수식 엔진 비교",
    "",
    `- 고정 자료 ${s.fixtures}개, 엔진 ${s.engines.length}개`,
    "- 해석 성공 열은 비어 있다 — Dart 쪽 검사가 채운다(07-sync 6.9.3, Q5)",
    "- 지연은 엔진 호출 ms의 중앙값·p90(가장 가까운 순위), 비용은 도구 안 단가로 계산한 추정이다",
    "",
    "| 엔진 | 판 | 호출 | 정확 일치 | 정규화 일치 | 해석 성공 | 지연 중앙값 ms | 지연 p90 ms | 실패 | 비용 USD |",
    "|---|---|---|---|---|---|---|---|---|---|",
  ];
  for (const e of s.engines) {
    if (!e.configured) {
      lines.push(`| ${e.engine} | — | 0 | 설정 안 됨 | 설정 안 됨 |  | — | — | — | — |`);
      continue;
    }
    const failures =
      e.failures.length === 0 ? "—" : e.failures.map(([kind, n]) => `${kind} ${n}`).join(", ");
    lines.push(
      [
        "",
        e.engine,
        e.versions.length === 0 ? "—" : e.versions.join(", "),
        String(e.calls),
        ratio(e.exact, e.rows),
        ratio(e.normalized, e.rows),
        "",
        e.medianMs === null ? "—" : String(Math.round(e.medianMs)),
        e.p90Ms === null ? "—" : String(Math.round(e.p90Ms)),
        failures,
        e.costUsd.toFixed(4),
        "",
      ].join(" | ").trim(),
    );
  }
  return lines.join("\n") + "\n";
}
