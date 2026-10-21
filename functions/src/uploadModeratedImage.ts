// functions/src/uploadModeratedImage.ts
//
// Firebase Cloud Function (callable) that moderates an image and, only if
// it passes, uploads it to Cloudinary — both server-side, in one step.
//
// WHY: before this, the app asked moderateImage "is this safe?" and then
// uploaded to Cloudinary ITSELF, signing the request with
// CLOUDINARY_API_SECRET read from the bundled .env. That meant (1) the
// Cloudinary secret shipped inside every APK/web build, and (2) moderation
// was only a check the client chose to run — anyone holding the secret
// could upload straight to Cloudinary and skip it. Here the secret lives
// only in Cloud Functions secrets, and the only way this function uploads
// is after checkSafeSearch says the image is safe.
//
// MODERATION (the server is the authority — nothing the client says is trusted):
//   1. the file's REAL type is read from its bytes (PNG / WebP / SVG) and must
//      match the extension; the type, not the extension, decides what runs
//   2. file-name blocked terms — also checked client-side as an early reject
//      (moderation_terms.dart), re-checked here (moderationTerms.ts)
//   3. Google Vision SafeSearch — checkSafeSearch (safeSearch.ts), fail closed
// SVG can't be analyzed by Vision, so it is limited to image_manager (admin)
// and must pass a structural safety check (no scripts, embedded images or
// external references) instead.
//
// OPT-OUT: the "Moderación automática" switch of the upload preview sends
// skipModeration, which skips ONLY the Vision call (to save cost); every check
// above still runs. The moderation mode is the fixed MODERATION_MODE
// (moderationPolicy.ts), never something the client sends.
//
// AUTH: Firebase-authenticated teacher or image_manager only (the two
// roles with an image library). The Cloudinary folder is derived here from
// the caller's role/uid — same rule as getUploadFolder() in
// image_service.dart — never trusted from the client.

import { onCall, HttpsError } from "firebase-functions/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import { getFirestore } from "firebase-admin/firestore";
import { createHash } from "crypto";
import { checkSafeSearch } from "./safeSearch";
import { MODERATION_MODE } from "./moderationPolicy";
import { findBlockedTermInFileName } from "./moderationTerms";

const CLOUDINARY_API_KEY = defineSecret("CLOUDINARY_API_KEY");
const CLOUDINARY_API_SECRET = defineSecret("CLOUDINARY_API_SECRET");
const GOOGLE_VISION_API_KEY = defineSecret("GOOGLE_VISION_API_KEY");
const CLOUD_NAME = "dmflzlyzk"; // same constant as ImageService.cloudName
const UPLOAD_PRESET = "multimedia"; // same as ImageService.uploadPreset

const MIME_BY_EXTENSION: Record<string, string> = {
  png: "image/png",
  webp: "image/webp",
  svg: "image/svg+xml",
};

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

type DetectedType = "png" | "webp" | "svg";

/**
 * Identifies an image by its bytes, ignoring the declared file name.
 * @param {Buffer} bytes The decoded file.
 * @return {DetectedType | null} The real type, or null if not PNG/WebP/SVG.
 */
function detectImageType(bytes: Buffer): DetectedType | null {
  const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length >= 8 && pngSignature.every((b, i) => bytes[i] === b)) {
    return "png";
  }
  if (
    bytes.length >= 12 &&
    bytes.toString("ascii", 0, 4) === "RIFF" &&
    bytes.toString("ascii", 8, 12) === "WEBP"
  ) {
    return "webp";
  }
  const head = bytes
    .toString("utf8", 0, Math.min(bytes.length, 4096))
    .replace(/^﻿/, "")
    .trimStart();
  if (head.startsWith("<") && /<svg[\s>]/i.test(head)) return "svg";
  return null;
}

// Things an SVG must not contain: scripts, event handlers, embedded raster
// images (which would dodge Vision), and any reference to anything outside
// the file.
const UNSAFE_SVG_PATTERNS: RegExp[] = [
  /<script/i,
  /\son[a-z]+\s*=/i,
  /<foreignObject/i,
  /<image[\s>]/i,
  /javascript:/i,
  /<!DOCTYPE/i,
  /<!ENTITY/i,
  /@import/i,
  /url\(\s*["']?\s*(?:https?:|data:)/i,
  /href\s*=\s*["']\s*(?!#)/i, // any href that isn't an internal "#id"
];

/**
 * @param {Buffer} bytes A decoded SVG file.
 * @return {boolean} true if it has no scripts, embedded images or external refs.
 */
function isSafeSvg(bytes: Buffer): boolean {
  const text = bytes.toString("utf8");
  return !UNSAFE_SVG_PATTERNS.some((pattern) => pattern.test(text));
}

interface UploadModeratedImageRequest {
  imageBase64?: string; // sin el prefijo data:...
  fileName?: string; // e.g. "perro.png" — solo se usa la extensión
  categoryName?: string; // nombre "folder-safe" de la categoría (opcional)
  // Solo una SOLICITUD del interruptor "Moderación automática": omite la
  // llamada a Vision. El modo de moderación nunca lo manda el cliente.
  skipModeration?: boolean;
}

type UploadModeratedImageResponse =
  | {
      success: true;
      secure_url: string;
      public_id: string;
      format: string;
      // true when Google Vision actually analyzed the image (false for SVG
      // and for a "Moderación automática" opt-out). The app stores it as
      // `isModerated` on the image's mediaLibrary document.
      moderationApplied: boolean;
    }
  | { success: false; reason: string };

export const uploadModeratedImage = onCall<
  UploadModeratedImageRequest,
  Promise<UploadModeratedImageResponse>
>(
  {
    secrets: [CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET, GOOGLE_VISION_API_KEY],
    maxInstances: 2,
  },
  async (request) => {
    // ── 1. Who is calling? ──────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }
    const uid = request.auth.uid;
    const userDoc = await getFirestore().collection("users").doc(uid).get();
    const role = userDoc.data()?.role as string | undefined;
    if (role !== "teacher" && role !== "image_manager") {
      throw new HttpsError("permission-denied", "Only teachers and image managers can upload images.");
    }

    // ── 2. Validate the input ───────────────────────────────────────────
    const { imageBase64, fileName, categoryName } = request.data;
    if (!imageBase64 || !fileName) {
      throw new HttpsError("invalid-argument", "imageBase64 and fileName are required.");
    }
    const extension = fileName.split(".").pop()?.toLowerCase() ?? "";
    if (!MIME_BY_EXTENSION[extension]) {
      return { success: false, reason: "UNSUPPORTED_FILE_FORMAT" };
    }
    const blockedTerm = findBlockedTermInFileName(fileName);
    if (blockedTerm) {
      logger.info(`uploadModeratedImage: rejected for ${uid} (file name term "${blockedTerm}")`);
      return { success: false, reason: "REJECT_INAPPROPRIATE_IMAGE" };
    }
    // What the file really is comes from its bytes, never from the name the
    // client sent: a photo renamed ".svg" must not skip Vision.
    const bytes = Buffer.from(imageBase64, "base64");
    if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) {
      return { success: false, reason: "UNSUPPORTED_FILE_FORMAT" };
    }
    const detectedType = detectImageType(bytes);
    if (detectedType !== extension) {
      logger.info(`uploadModeratedImage: ${uid} sent "${fileName}" but the bytes are ${detectedType}`);
      return { success: false, reason: "UNSUPPORTED_FILE_FORMAT" };
    }
    const mimeType = MIME_BY_EXTENSION[detectedType];
    // Only letters, digits, "_" and "-": the category becomes part of a
    // Cloudinary folder path, so no "/" or ".." tricks.
    if (categoryName && !/^[A-Za-z0-9_-]+$/.test(categoryName)) {
      throw new HttpsError("invalid-argument", "Invalid categoryName.");
    }

    // ── 3. Moderate — nothing is uploaded unless this passes ────────────
    let moderationApplied = false;
    if (detectedType === "svg") {
      // Vision can't analyze vector images, so SVG is restricted to the
      // image manager and must pass the structural safety check.
      if (role !== "image_manager") {
        return { success: false, reason: "SVG_NOT_ALLOWED" };
      }
      if (!isSafeSvg(bytes)) {
        logger.info(`uploadModeratedImage: rejected SVG for ${uid} (unsafe content)`);
        return { success: false, reason: "UNSAFE_SVG" };
      }
    } else {
      // The moderation mode is fixed on the server (MODERATION_MODE) — the
      // client never sends one. The client only ASKS to skip Vision (the
      // "Moderación automática" switch); only teachers and the image manager
      // reach this function, and everything above (auth, role, real file
      // type, size, file name) still applied.
      if (request.data.skipModeration === true) {
        logger.warn(`uploadModeratedImage: Vision analysis skipped for ${uid} (${role}, opt-out)`);
      } else {
        const moderation = await checkSafeSearch(
          imageBase64,
          GOOGLE_VISION_API_KEY.value(),
          MODERATION_MODE,
          fileName
        );
        if (!moderation.safe) {
          logger.info(
            `uploadModeratedImage: rejected for ${uid} (${moderation.reason}, ${MODERATION_MODE} mode)`
          );
          return { success: false, reason: moderation.reason };
        }
        moderationApplied = true;
      }
    }

    // ── 4. Upload to Cloudinary with the server-only secret ────────────
    const baseFolder = role === "image_manager" ? "imagesPredefined" : `teacherUploads/${uid}`;
    const folder = categoryName ? `${baseFolder}/${categoryName}` : baseFolder;
    const timestamp = Math.floor(Date.now() / 1000).toString();

    // Cloudinary's signature: sha1 over the alphabetically-sorted
    // param=value pairs (excluding file/api_key), plus the secret — same
    // recipe as ttsCacheStorage.ts.
    const toSign = `folder=${folder}&timestamp=${timestamp}&upload_preset=${UPLOAD_PRESET}` +
      CLOUDINARY_API_SECRET.value();
    const signature = createHash("sha1").update(toSign).digest("hex");

    const form = new FormData();
    form.append("file", `data:${mimeType};base64,${imageBase64}`);
    form.append("folder", folder);
    form.append("timestamp", timestamp);
    form.append("upload_preset", UPLOAD_PRESET);
    form.append("api_key", CLOUDINARY_API_KEY.value());
    form.append("signature", signature);

    try {
      const response = await fetch(
        `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/image/upload`,
        { method: "POST", body: form }
      );

      if (!response.ok) {
        const errText = await response.text().catch(() => "");
        logger.error("uploadModeratedImage: Cloudinary upload failed", {
          status: response.status,
          body: errText,
        });
        return { success: false, reason: "UPLOAD_FAILED" };
      }

      const json = (await response.json()) as {
        secure_url: string;
        public_id: string;
        format: string;
      };
      return {
        success: true,
        secure_url: json.secure_url,
        public_id: json.public_id,
        format: json.format,
        moderationApplied,
      };
    } catch (error: unknown) {
      logger.error("uploadModeratedImage error:", error);
      return { success: false, reason: "UPLOAD_FAILED" };
    }
  }
);
