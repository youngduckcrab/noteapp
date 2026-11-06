// Engine LaTeX cleaning and the comparison tool's normalisation (07-sync 6.9.3).

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { normalizeLatex, stripMathDelimiters } from "../src/engines/latex.js";

describe("stripMathDelimiters", () => {
  for (const [input, expected] of [
    ["  x^2  ", "x^2"],
    ["$x^2$", "x^2"],
    ["$$ x^2 $$", "x^2"],
    ["\\[x^2\\]", "x^2"],
    ["\\(x^2\\)", "x^2"],
    ["$a$ and $b$", "a$ and $b"],
    ["$", "$"],
    ["\\frac{1}{2}", "\\frac{1}{2}"],
  ] as const) {
    it(`${JSON.stringify(input)} → ${JSON.stringify(expected)}`, () => {
      assert.equal(stripMathDelimiters(input), expected);
    });
  }

  it("removes one pair only", () => {
    assert.equal(stripMathDelimiters("$$$x$$$"), "$x$");
  });
});

describe("normalizeLatex", () => {
  for (const [a, b] of [
    ["\\frac{a}{b}", " \\frac { a } { b } "],
    ["\\frac{1}{2}", "\\dfrac{1}{2}"],
    ["\\frac{1}{2}", "\\tfrac{1}{2}"],
    ["(x+1)", "\\left(x+1\\right)"],
    ["x^2", "x^{2}"],
    ["a_i", "a_{i}"],
    ["x^{10}", "x^{10}"],
    ["\\sin x", "\\operatorname{sin} x"],
    ["ab", "a\\,b"],
    ["ab", "a\\;b\\!"],
    ["ab", "a\\quad b"],
    ["ab", "a\\qquad b"],
    ["ab", "a\\ b"],
    ["x^2", "$x^2$"],
    ["x^2", "\\[ x^{2} \\]"],
  ] as const) {
    it(`${JSON.stringify(a)} ≡ ${JSON.stringify(b)}`, () => {
      assert.equal(normalizeLatex(a), normalizeLatex(b));
    });
  }

  for (const [a, b] of [
    ["\\frac{1}{2}", "\\frac{2}{1}"],
    ["x^2", "x_2"],
    ["\\leftarrow", "arrow"],
    ["\\quadrant", "rant"],
    ["x^{ab}", "x^ab"],
  ] as const) {
    it(`${JSON.stringify(a)} ≢ ${JSON.stringify(b)}`, () => {
      assert.notEqual(normalizeLatex(a), normalizeLatex(b));
    });
  }

  it("is idempotent", () => {
    for (const s of ["\\left( \\dfrac{a}{b} \\right)^{2}", "$\\operatorname{cos}\\,x$"]) {
      assert.equal(normalizeLatex(normalizeLatex(s)), normalizeLatex(s));
    }
  });
});
