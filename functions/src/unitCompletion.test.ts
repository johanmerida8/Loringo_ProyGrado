// functions/src/unitCompletion.test.ts
//
// Covers the "Unit completed" milestone rule (unitCompletion.ts's
// isUnitDone) -- run with Node's built-in test runner (`npm test`), same
// as groupCode.test.ts, no Firestore or Cloud Functions runtime needed.

import { test } from "node:test";
import * as assert from "node:assert/strict";
import { isUnitDone } from "./unitCompletion";

test("1. all activities done and the Unit Quiz done -> unit completed", () => {
  assert.equal(isUnitDone(new Set(["a1", "a2", "uq"]), ["a1", "a2"], ["uq"]), true);
});

test("2. all activities done but the Unit Quiz not taken -> not completed", () => {
  assert.equal(isUnitDone(new Set(["a1", "a2"]), ["a1", "a2"], ["uq"]), false);
});

test("3. Unit Quiz done but one activity missing -> not completed", () => {
  assert.equal(isUnitDone(new Set(["a1", "uq"]), ["a1", "a2"], ["uq"]), false);
});

test("4. a unit without a Unit Quiz is completed once all activities are", () => {
  assert.equal(isUnitDone(new Set(["a1", "a2"]), ["a1", "a2"], []), true);
});

test("5. Lesson Quizzes don't count toward finishing the unit", () => {
  // Only a lesson quiz completed besides the activities -> still missing uq.
  assert.equal(isUnitDone(new Set(["a1", "lq1"]), ["a1"], ["uq"]), false);
});

test("6. a unit with no activities is never reported as completed", () => {
  assert.equal(isUnitDone(new Set(["uq"]), [], ["uq"]), false);
});
