// functions/src/groupCode.ts
//
// Server-side group-code security. Mirrors the student access-code
// approach (lib/utils/access_code_hasher.dart / access_code_cipher.dart —
// HMAC-SHA256 hash for lookup, AES-256-GCM for reversible reveal) but
// deliberately keeps the pepper/key ONLY in Cloud Functions Secrets,
// never in the compiled Flutter client — the exact gap flagged in this
// session's security review of the access-code implementation, where the
// pepper/key had to ship inside the app because hashing/encryption ran
// client-side in Dart.
//
// WHY THIS CAN'T BE CLIENT-SIDE: same reasoning as
// deleteCloudinaryImage.ts/listCloudinaryAvatars.ts — any secret used to
// derive a hash/cipher must live only on the server, or it isn't actually
// secret. group codes are less sensitive than a minor's access code, but
// the same principle applies: `teacherGroups/{groupId}` is world-readable
// (allow read: if true, needed for group name/roster visibility), so
// whatever field holds the code must never be the plaintext itself.

import { onCall, HttpsError } from "firebase-functions/https";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as crypto from "crypto";

const GROUP_CODE_PEPPER = defineSecret("GROUP_CODE_PEPPER");
const GROUP_CODE_KEY = defineSecret("GROUP_CODE_KEY");

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no O/0/I/1

// ── Pure helpers (no Firebase imports) — unit-tested directly in
// groupCode.test.ts, independent of the Functions runtime. ──────────────

/**
 * Cryptographically secure 6-character group code.
 * @return {string} A 6-character code from CODE_ALPHABET.
 */
export function generateSecureCode(): string {
  let code = "";
  for (let i = 0; i < 6; i++) {
    const index = crypto.randomInt(CODE_ALPHABET.length);
    code += CODE_ALPHABET[index];
  }
  return code;
}

/**
 * HMAC-SHA256 of the normalized code, keyed with the pepper.
 * @param {string} code The raw group code.
 * @param {string} pepper The server-side HMAC key.
 * @return {string} Hex-encoded HMAC digest.
 */
export function hashGroupCode(code: string, pepper: string): string {
  return crypto
    .createHmac("sha256", pepper)
    .update(code.trim().toUpperCase())
    .digest("hex");
}

/**
 * AES-256-GCM encrypt. `keyBase64` must decode to 32 bytes.
 * @param {string} code The raw group code to encrypt.
 * @param {string} keyBase64 Base64-encoded 32-byte AES key.
 * @return {string} "iv:ciphertext:authTag", each base64-encoded.
 */
export function encryptGroupCode(code: string, keyBase64: string): string {
  const key = Buffer.from(keyBase64, "base64");
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(code.trim().toUpperCase(), "utf8"),
    cipher.final(),
  ]);
  const authTag = cipher.getAuthTag();
  // iv:ciphertext:authTag, all base64 — mirrors AccessCodeCipher's
  // "iv:ciphertext" shape, with the GCM auth tag appended (Dart's
  // pointycastle GCMBlockCipher appends the tag to the ciphertext
  // automatically; Node's crypto module keeps it separate, so it must be
  // stored explicitly here).
  return `${iv.toString("base64")}:${ciphertext.toString("base64")}:${authTag.toString("base64")}`;
}

/**
 * Reverses encryptGroupCode. Throws if the value/key don't match (GCM auth failure).
 * @param {string} encrypted "iv:ciphertext:authTag" as produced by encryptGroupCode.
 * @param {string} keyBase64 Base64-encoded 32-byte AES key.
 * @return {string} The original plaintext group code.
 */
export function decryptGroupCode(encrypted: string, keyBase64: string): string {
  const parts = encrypted.split(":");
  if (parts.length !== 3) throw new Error("Malformed encrypted group code");
  const [ivB64, ciphertextB64, authTagB64] = parts;
  const key = Buffer.from(keyBase64, "base64");
  const iv = Buffer.from(ivB64, "base64");
  const authTag = Buffer.from(authTagB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(authTag);
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(ciphertextB64, "base64")),
    decipher.final(),
  ]);
  return plaintext.toString("utf8");
}

/**
 * Fields to write for a fresh/migrated code — used by generate, reveal
 * (legacy migration), and findByCode (legacy migration). Never includes
 * the plaintext code itself.
 * @param {string} code The raw group code.
 * @param {string} pepper The server-side HMAC key.
 * @param {string} keyBase64 Base64-encoded 32-byte AES key.
 * @return {{groupCodeHash: string, groupCodeEncrypted: string}} Fields to persist.
 */
export function buildGroupCodeFields(
  code: string,
  pepper: string,
  keyBase64: string
): { groupCodeHash: string; groupCodeEncrypted: string } {
  return {
    groupCodeHash: hashGroupCode(code, pepper),
    groupCodeEncrypted: encryptGroupCode(code, keyBase64),
  };
}

/**
 * The ownership check revealGroupCode enforces — pulled out as a pure
 * predicate so it's testable without a full request/auth object.
 * @param {string | undefined} callerUid The requesting user's uid.
 * @param {string | undefined} groupTeacherId The group's owning teacherId.
 * @return {boolean} True if the caller owns the group.
 */
export function callerOwnsGroup(
  callerUid: string | undefined,
  groupTeacherId: string | undefined
): boolean {
  return !!callerUid && !!groupTeacherId && callerUid === groupTeacherId;
}

// ── Callables ─────────────────────────────────────────────────────────

interface GenerateGroupCodeResponse {
  groupCode: string;
  groupCodeHash: string;
  groupCodeEncrypted: string;
}

/** Generates a new, unique group code. The client still creates the
 * teacherGroups document itself (name/color/etc.) — this only produces
 * the three code-related fields, keeping the change to the existing
 * create-group flow in teacher_home_screen.dart minimal. */
export const generateGroupCode = onCall<
  unknown,
  Promise<GenerateGroupCodeResponse>
>(
  { secrets: [GROUP_CODE_PEPPER, GROUP_CODE_KEY], maxInstances: 2 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }

    const pepper = GROUP_CODE_PEPPER.value();
    const key = GROUP_CODE_KEY.value();
    const db = getFirestore();

    let code: string;
    let hash: string;
    // Loop until a non-colliding hash is found — same approach as
    // Database._uniqueAccessCode() on the Dart side.
    for (;;) {
      code = generateSecureCode();
      hash = hashGroupCode(code, pepper);
      const existing = await db
        .collection("teacherGroups")
        .where("groupCodeHash", "==", hash)
        .limit(1)
        .get();
      if (existing.empty) break;
    }

    return {
      groupCode: code,
      groupCodeHash: hash,
      groupCodeEncrypted: encryptGroupCode(code, key),
    };
  }
);

interface RevealGroupCodeRequest {
  groupId?: string;
}

/** Decrypts and returns a group's static code — only for the teacher who
 * owns it. Self-heals legacy plaintext `groupCode` docs (pre-dating this
 * change) in place, same self-heal pattern as
 * Database.revealAccessCode/findStudentByAccessCode on the Dart side. */
export const revealGroupCode = onCall<
  RevealGroupCodeRequest,
  Promise<{ groupCode: string }>
>(
  { secrets: [GROUP_CODE_PEPPER, GROUP_CODE_KEY], maxInstances: 2 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }
    const groupId = (request.data?.groupId ?? "").trim();
    if (!groupId) {
      throw new HttpsError("invalid-argument", "groupId is required.");
    }

    const pepper = GROUP_CODE_PEPPER.value();
    const key = GROUP_CODE_KEY.value();
    const db = getFirestore();
    const groupRef = db.collection("teacherGroups").doc(groupId);
    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      throw new HttpsError("not-found", "Group not found.");
    }
    const data = groupSnap.data() ?? {};

    if (!callerOwnsGroup(request.auth.uid, data.teacherId)) {
      throw new HttpsError(
        "permission-denied",
        "Only the owning teacher can view this group's code."
      );
    }

    const encrypted = data.groupCodeEncrypted as string | undefined;
    if (encrypted) {
      const code = decryptGroupCode(encrypted, key);
      const expectedHash = hashGroupCode(code, pepper);
      if (data.groupCodeHash !== expectedHash) {
        await groupRef.update({ groupCodeHash: expectedHash });
      }
      return { groupCode: code };
    }

    const legacyPlaintext = data.groupCode as string | undefined;
    if (legacyPlaintext) {
      const fields = buildGroupCodeFields(legacyPlaintext, pepper, key);
      await groupRef.update({ ...fields, groupCode: FieldValue.delete() });
      return { groupCode: legacyPlaintext };
    }

    throw new HttpsError("not-found", "No access code found for this group.");
  }
);

interface FindGroupByCodeRequest {
  code?: string;
}

interface FindGroupByCodeResponse {
  groupId: string;
  name: string;
  archived: boolean;
  teacherId: string;
}

/** Looks up a group by its join code for a parent/student trying to
 * join — hashes the input and queries groupCodeHash, falling back to (and
 * migrating) a legacy plaintext groupCode doc. Returns `archived` rather
 * than filtering it out here, so the client keeps its existing distinct
 * "invalid code" vs. "group not accepting members" messaging. */
export const findGroupByCode = onCall<
  FindGroupByCodeRequest,
  Promise<FindGroupByCodeResponse | null>
>(
  { secrets: [GROUP_CODE_PEPPER, GROUP_CODE_KEY], maxInstances: 2 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }
    const code = (request.data?.code ?? "").trim();
    if (!code) {
      throw new HttpsError("invalid-argument", "code is required.");
    }

    const pepper = GROUP_CODE_PEPPER.value();
    const key = GROUP_CODE_KEY.value();
    const db = getFirestore();
    const hash = hashGroupCode(code, pepper);

    const hashSnap = await db
      .collection("teacherGroups")
      .where("groupCodeHash", "==", hash)
      .limit(1)
      .get();
    if (!hashSnap.empty) {
      const doc = hashSnap.docs[0];
      const data = doc.data();
      return {
        groupId: doc.id,
        name: data.name ?? "",
        archived: data.archived === true,
        teacherId: data.teacherId ?? "",
      };
    }

    const legacySnap = await db
      .collection("teacherGroups")
      .where("groupCode", "==", code.toUpperCase())
      .limit(1)
      .get();
    if (legacySnap.empty) return null;

    const legacyDoc = legacySnap.docs[0];
    const legacyData = legacyDoc.data();
    const fields = buildGroupCodeFields(code, pepper, key);
    await legacyDoc.ref.update({ ...fields, groupCode: FieldValue.delete() });
    return {
      groupId: legacyDoc.id,
      name: legacyData.name ?? "",
      archived: legacyData.archived === true,
      teacherId: legacyData.teacherId ?? "",
    };
  }
);
