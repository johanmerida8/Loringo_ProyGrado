// functions/src/moderationPolicy.test.ts
//
// Tests of the image-moderation policy: the SafeSearch thresholds of each
// mode (including POSSIBLE), and that Vision failures NEVER approve an image.
// Run with `npm test` (node:test over the compiled output, like the others).
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  SafeSearchAnnotation,
  evaluateContent,
  evaluateSafeSearch,
  parseModerationMode,
} from "./moderationPolicy";
import { checkSafeSearch } from "./safeSearch";

// A fully clean annotation, overridden per test.
const clean: SafeSearchAnnotation = {
  adult: "VERY_UNLIKELY",
  medical: "VERY_UNLIKELY",
  spoof: "VERY_UNLIKELY",
  violence: "VERY_UNLIKELY",
  racy: "VERY_UNLIKELY",
};
const withLevel = (category: keyof SafeSearchAnnotation, level: string): SafeSearchAnnotation =>
  ({ ...clean, [category]: level });

// ── Legitimate image ──────────────────────────────────────────────────────
for (const mode of ["normal", "strict"] as const) {
  test(`${mode}: a clean image is approved`, () => {
    assert.deepEqual(evaluateSafeSearch(clean, mode), { safe: true });
  });
  test(`${mode}: UNLIKELY everywhere is approved`, () => {
    const unlikely = { ...clean, adult: "UNLIKELY", racy: "UNLIKELY", violence: "UNLIKELY" };
    assert.deepEqual(evaluateSafeSearch(unlikely, mode), { safe: true });
  });
}

// ── Inappropriate image: blocked in both modes ────────────────────────────
for (const mode of ["normal", "strict"] as const) {
  for (const category of ["adult", "racy", "violence", "medical"] as const) {
    for (const level of ["LIKELY", "VERY_LIKELY"]) {
      test(`${mode}: ${category} ${level} is rejected`, () => {
        const verdict = evaluateSafeSearch(withLevel(category, level), mode);
        assert.equal(verdict.safe, false);
        assert.equal(!verdict.safe && verdict.reason, "REJECT_INAPPROPRIATE_IMAGE");
      });
    }
  }
}

// ── Uncertain (POSSIBLE): the difference between the modes ────────────────
for (const category of ["adult", "violence"] as const) {
  test(`normal: ${category} POSSIBLE passes`, () => {
    assert.deepEqual(evaluateSafeSearch(withLevel(category, "POSSIBLE"), "normal"), { safe: true });
  });
}
for (const category of ["adult", "racy", "violence"] as const) {
  test(`strict: ${category} POSSIBLE is rejected`, () => {
    const verdict = evaluateSafeSearch(withLevel(category, "POSSIBLE"), "strict");
    assert.equal(verdict.safe, false);
    assert.equal(!verdict.safe && verdict.reason, "REJECT_INAPPROPRIATE_IMAGE");
  });
}

// racy POSSIBLE (a semi-naked person) is rejected in BOTH modes.
test("racy POSSIBLE is rejected in both modes", () => {
  for (const mode of ["normal", "strict"] as const) {
    const verdict = evaluateSafeSearch(withLevel("racy", "POSSIBLE"), mode);
    assert.equal(verdict.safe, false, mode);
    assert.equal(!verdict.safe && verdict.reason, "REJECT_INAPPROPRIATE_IMAGE");
  }
});

// The real SafeSearch of a shirtless-bodybuilder photo that slipped through.
test("racy POSSIBLE + spoof POSSIBLE with adult VERY_UNLIKELY (shirtless photo) is rejected", () => {
  const shirtless = { ...clean, racy: "POSSIBLE", spoof: "POSSIBLE" };
  for (const mode of ["normal", "strict"] as const) {
    assert.equal(evaluateSafeSearch(shirtless, mode).safe, false, mode);
  }
});

test("medical POSSIBLE passes in both modes (only LIKELY blocks it)", () => {
  for (const mode of ["normal", "strict"] as const) {
    assert.deepEqual(evaluateSafeSearch(withLevel("medical", "POSSIBLE"), mode), { safe: true });
  }
});

test("spoof never blocks, even VERY_LIKELY", () => {
  for (const mode of ["normal", "strict"] as const) {
    assert.deepEqual(evaluateSafeSearch(withLevel("spoof", "VERY_LIKELY"), mode), { safe: true });
  }
});

// ── Unusable answers never approve ────────────────────────────────────────
for (const mode of ["normal", "strict"] as const) {
  test(`${mode}: no annotation is a service error`, () => {
    assert.deepEqual(evaluateSafeSearch(undefined, mode), {
      safe: false,
      reason: "MODERATION_SERVICE_ERROR",
    });
  });
  test(`${mode}: an UNKNOWN or missing category is a service error`, () => {
    for (const bad of [{ ...clean, adult: "UNKNOWN" }, { ...clean, racy: undefined }, {}]) {
      const verdict = evaluateSafeSearch(bad as SafeSearchAnnotation, mode);
      assert.equal(verdict.safe, false);
      assert.equal(!verdict.safe && verdict.reason, "MODERATION_SERVICE_ERROR");
    }
  });
}

// ── Labels and objects (weapons, alcohol, tobacco, drugs) ─────────────────
test("firearms are rejected in both modes when the score is high enough", () => {
  for (const mode of ["normal", "strict"] as const) {
    const verdict = evaluateContent([{ description: "Firearm", score: 0.9 }], [], mode);
    assert.equal(verdict.safe, false);
    assert.equal(!verdict.safe && verdict.reason, "REJECT_INAPPROPRIATE_IMAGE");
  }
});

test("a firearm label under the mode's minimum score passes", () => {
  assert.deepEqual(evaluateContent([{ description: "Handgun", score: 0.6 }], [], "normal"), { safe: true });
  assert.equal(evaluateContent([{ description: "Handgun", score: 0.6 }], [], "strict").safe, false);
});

test("normal lets a knife and a toy gun through; strict rejects them", () => {
  for (const description of ["Kitchen knife", "Water gun"]) {
    const labels = [{ description, score: 0.9 }];
    assert.deepEqual(evaluateContent(labels, [], "normal"), { safe: true }, description);
    assert.equal(evaluateContent(labels, [], "strict").safe, false, description);
  }
});

test("drugs, pills, syringes, alcohol and tobacco are rejected in both modes", () => {
  for (const description of [
    "Pharmaceutical drug", "Prescription drug", "Pill", "Syringe",
    "Cocaine", "Cannabis", "Beer", "Wine", "Alcohol", "Cigarette", "Tobacco",
  ]) {
    const labels = [{ description, score: 0.9 }];
    for (const mode of ["normal", "strict"] as const) {
      assert.equal(evaluateContent(labels, [], mode).safe, false, `${mode}: ${description}`);
    }
  }
});

test("objects are checked like labels", () => {
  const objects = [{ name: "Knife", score: 0.8 }];
  assert.equal(evaluateContent([], objects, "normal").safe, true);
  assert.equal(evaluateContent([], objects, "strict").safe, false);
  assert.equal(evaluateContent([], [{ name: "Shotgun", score: 0.9 }], "normal").safe, false);
  for (const mode of ["normal", "strict"] as const) {
    assert.equal(evaluateContent([], [{ name: "Syringe", score: 0.83 }], mode).safe, false);
  }
});

// The two real images that slipped through (labels as Vision returned them).
test("a photo of pills / medicine, as Vision labeled it, is rejected in both modes", () => {
  const labels = [
    { description: "Pharmaceutical drug", score: 0.97 },
    { description: "Medicine", score: 0.97 },
    { description: "Pill", score: 0.93 },
    { description: "Capsule", score: 0.79 },
  ];
  for (const mode of ["normal", "strict"] as const) {
    assert.equal(evaluateContent(labels, [{ name: "Syringe", score: 0.83 }], mode).safe, false);
  }
});

test("white powder in a plastic bag (labeled only Powder + Bag) is rejected in both modes", () => {
  const labels = [
    { description: "White", score: 0.97 },
    { description: "Powder", score: 0.85 },
    { description: "Plastic", score: 0.74 },
    { description: "Plastic bag", score: 0.69 },
  ];
  for (const mode of ["normal", "strict"] as const) {
    const verdict = evaluateContent(labels, [{ name: "Bag", score: 0.54 }], mode);
    assert.equal(verdict.safe, false);
    assert.equal(!verdict.safe && verdict.category, "combo:powder+bag");
  }
});

test("powder without a bag (flour, paint) and a bag without powder pass", () => {
  for (const mode of ["normal", "strict"] as const) {
    assert.deepEqual(evaluateContent([{ description: "Powder", score: 0.9 }], [], mode), { safe: true });
    assert.deepEqual(evaluateContent([{ description: "Plastic bag", score: 0.9 }], [{ name: "Bag", score: 0.9 }], mode), { safe: true });
  }
});

test("harmless labels and empty or missing lists pass in both modes", () => {
  for (const mode of ["normal", "strict"] as const) {
    assert.deepEqual(evaluateContent([{ description: "Cartoon", score: 0.99 }], [{ name: "Toy", score: 0.9 }], mode), { safe: true });
    assert.deepEqual(evaluateContent([], [], mode), { safe: true });
    assert.deepEqual(evaluateContent(undefined, undefined, mode), { safe: true });
  }
  // A blocked word inside a bigger word must not match ("Gunnera" is a plant).
  assert.deepEqual(evaluateContent([{ description: "Gunnera", score: 0.95 }], [], "strict"), { safe: true });
});

test("checkSafeSearch rejects a clean SafeSearch image with a weapon label", async () => {
  stubFetch(async () => jsonResponse({
    responses: [{
      safeSearchAnnotation: clean,
      labelAnnotations: [{ description: "Pistol", score: 0.93 }],
    }],
  }));
  try {
    for (const mode of ["normal", "strict"] as const) {
      const verdict = await checkSafeSearch("aGVsbG8=", "test-key", mode);
      assert.equal(verdict.safe, false);
      assert.equal(!verdict.safe && verdict.reason, "REJECT_INAPPROPRIATE_IMAGE");
    }
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("parseModerationMode accepts only the two modes", () => {
  assert.equal(parseModerationMode("normal"), "normal");
  assert.equal(parseModerationMode("strict"), "strict");
  for (const bad of ["off", "", "STRICT", undefined, null, 1, {}]) {
    assert.equal(parseModerationMode(bad), null);
  }
});

// ── Vision API failures (fetch is replaced): never approved ───────────────
const realFetch = globalThis.fetch;
const stubFetch = (impl: () => Promise<unknown>) => {
  globalThis.fetch = (async () => impl()) as unknown as typeof fetch;
};
const jsonResponse = (body: unknown, ok = true, status = 200) =>
  ({ ok, status, json: async () => body }) as unknown;

const failures: [string, () => Promise<unknown>][] = [
  ["HTTP error", async () => jsonResponse({}, false, 500)],
  ["network error", async () => { throw new Error("network down"); }],
  ["invalid JSON", async () => ({ ok: true, status: 200, json: async () => { throw new Error("bad json"); } })],
  ["empty responses", async () => jsonResponse({ responses: [] })],
  ["no responses field", async () => jsonResponse({})],
  ["per-image error", async () => jsonResponse({ responses: [{ error: { code: 3, message: "bad image" } }] })],
  ["no annotation", async () => jsonResponse({ responses: [{}] })],
  ["unrated category", async () => jsonResponse({ responses: [{ safeSearchAnnotation: { ...clean, adult: "UNKNOWN" } }] })],
];

for (const mode of ["normal", "strict"] as const) {
  for (const [name, impl] of failures) {
    test(`${mode}: Vision failure (${name}) is never approved`, async () => {
      stubFetch(impl);
      try {
        const verdict = await checkSafeSearch("aGVsbG8=", "test-key", mode);
        assert.equal(verdict.safe, false);
        assert.equal(!verdict.safe && verdict.reason, "MODERATION_SERVICE_ERROR");
      } finally {
        globalThis.fetch = realFetch;
      }
    });
  }

  test(`${mode}: a good Vision answer is evaluated with the mode's policy`, async () => {
    // adult POSSIBLE: the one result where the two modes differ.
    stubFetch(async () => jsonResponse({ responses: [{ safeSearchAnnotation: withLevel("adult", "POSSIBLE") }] }));
    try {
      const verdict = await checkSafeSearch("aGVsbG8=", "test-key", mode);
      assert.equal(verdict.safe, mode === "normal");
    } finally {
      globalThis.fetch = realFetch;
    }
  });
}
