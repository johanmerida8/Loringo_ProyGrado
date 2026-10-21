// functions/src/groupCode.test.ts
//
// Covers the 6 requested scenarios against groupCode.ts's pure,
// framework-free functions — run with Node's built-in test runner
// (`node --test`, see package.json's "test" script), no new dependency.
// These exercise the exact logic the onCall handlers (generateGroupCode,
// revealGroupCode, findGroupByCode) delegate to, without needing the
// Cloud Functions runtime or Admin SDK.

import { test } from "node:test";
import * as assert from "node:assert/strict";
import {
  generateSecureCode,
  hashGroupCode,
  encryptGroupCode,
  decryptGroupCode,
  buildGroupCodeFields,
  callerOwnsGroup,
} from "./groupCode";

const PEPPER = "test-pepper";
const KEY = Buffer.alloc(32, 7).toString("base64"); // 32 bytes, base64

test("1. groupCode is not stored in plaintext — buildGroupCodeFields never includes the raw code", () => {
  const code = generateSecureCode();
  const fields = buildGroupCodeFields(code, PEPPER, KEY);

  assert.equal(Object.keys(fields).sort().join(","), "groupCodeEncrypted,groupCodeHash");
  assert.notEqual(fields.groupCodeHash, code);
  assert.ok(!fields.groupCodeEncrypted.includes(code));
});

test("2. a valid group code can still be verified (hash matches)", () => {
  const code = "ABC123";
  const storedHash = hashGroupCode(code, PEPPER);

  assert.equal(hashGroupCode("ABC123", PEPPER), storedHash);
  // case/whitespace-insensitive, same normalization as AccessCodeHasher
  assert.equal(hashGroupCode(" abc123 ", PEPPER), storedHash);
});

test("3. an invalid group code is rejected (hash does not match)", () => {
  const storedHash = hashGroupCode("ABC123", PEPPER);
  assert.notEqual(hashGroupCode("WRONG1", PEPPER), storedHash);
});

test("4. an authorized teacher can retrieve/display their group code (decrypt round-trip)", () => {
  const code = generateSecureCode();
  const encrypted = encryptGroupCode(code, KEY);
  assert.equal(decryptGroupCode(encrypted, KEY), code);
});

test("4b. decrypting with the wrong key fails instead of returning garbage", () => {
  const code = generateSecureCode();
  const encrypted = encryptGroupCode(code, KEY);
  const wrongKey = Buffer.alloc(32, 9).toString("base64");
  assert.throws(() => decryptGroupCode(encrypted, wrongKey));
});

test("5. unauthorized users cannot retrieve the plaintext group code (ownership check)", () => {
  assert.equal(callerOwnsGroup("teacher_1", "teacher_1"), true);
  assert.equal(callerOwnsGroup("teacher_2", "teacher_1"), false);
  assert.equal(callerOwnsGroup(undefined, "teacher_1"), false);
  assert.equal(callerOwnsGroup("teacher_1", undefined), false);
});

test("6. existing (legacy plaintext) groups continue to work after migration", () => {
  // Simulates a teacherGroups doc created before this change: only a
  // plaintext `groupCode` field, no hash/encrypted fields yet.
  const legacyPlaintextCode = "OLDCOD";

  const fields = buildGroupCodeFields(legacyPlaintextCode, PEPPER, KEY);

  // The migrated doc's hash matches what a lookup would compute for the
  // original code — so findGroupByCode/revealGroupCode's fallback path
  // (query by legacy `groupCode`, then rewrite these fields) results in a
  // doc that verifies correctly from then on.
  assert.equal(hashGroupCode(legacyPlaintextCode, PEPPER), fields.groupCodeHash);
  // And the original code is still recoverable via decrypt — the teacher
  // sees the exact same code they had before, not a new one.
  assert.equal(decryptGroupCode(fields.groupCodeEncrypted, KEY), legacyPlaintextCode);
});
