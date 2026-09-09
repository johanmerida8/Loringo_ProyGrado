// functions/src/deleteCloudinaryImage.ts
//
// Firebase Cloud Function (callable) that deletes an image from Cloudinary
// via its admin "destroy" endpoint.
//
// WHY THIS CAN'T BE A DIRECT CLIENT CALL (unlike uploadToCloudinary in
// image_service.dart, which posts straight to Cloudinary from the app):
// Cloudinary's upload endpoint is designed for direct browser/client use
// and is CORS-enabled for that; the admin "destroy" endpoint is a
// privileged admin-API operation, requires Basic auth with the API
// secret, and is NOT CORS-enabled for browser callers — a direct client
// call on Flutter Web fails with a generic "Failed to fetch" (the browser
// blocking the cross-origin request, not a Cloudinary-side rejection).
// Moving it server-side sidesteps CORS entirely (server-to-server HTTP has
// no CORS concept) and, as a bonus, stops shipping CLOUDINARY_API_SECRET
// inside the compiled client bundle — same reasoning as moderateImage.ts's
// GOOGLE_VISION_API_KEY.
//
// AUTH: unlike moderateImage.ts/generateReadingAudio.ts (reachable by
// unauthenticated students), every caller of this function is a
// Firebase-authenticated teacher or admin (admin_view_images_screen.dart /
// teacher_view_images_screen.dart) — so, unlike those two, this one DOES
// require request.auth. A destructive delete on someone's media library
// shouldn't be callable by an anonymous client.

import { onCall, HttpsError } from "firebase-functions/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

const CLOUDINARY_API_KEY = defineSecret("CLOUDINARY_API_KEY");
const CLOUDINARY_API_SECRET = defineSecret("CLOUDINARY_API_SECRET");
const CLOUD_NAME = "dmflzlyzk"; // same constant as ImageService.cloudName

interface DeleteCloudinaryImageRequest {
  publicId?: string;
}

export const deleteCloudinaryImage = onCall<
  DeleteCloudinaryImageRequest,
  Promise<{ deleted: boolean }>
>(
  { secrets: [CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }

    const publicId = (request.data?.publicId ?? "").trim();
    if (!publicId) {
      throw new HttpsError("invalid-argument", "publicId is required.");
    }

    const apiKey = CLOUDINARY_API_KEY.value();
    const apiSecret = CLOUDINARY_API_SECRET.value();
    const auth = Buffer.from(`${apiKey}:${apiSecret}`).toString("base64");

    try {
      const response = await fetch(
        `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/image/destroy`,
        {
          method: "POST",
          headers: {
            "Authorization": `Basic ${auth}`,
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: `public_id=${encodeURIComponent(publicId)}`,
        }
      );

      if (!response.ok) {
        logger.error(`deleteCloudinaryImage: HTTP ${response.status} for ${publicId}`);
        return { deleted: false };
      }

      // Cloudinary returns HTTP 200 for both a real deletion
      // ({"result":"ok"}) and a no-op ({"result":"not found"}) — the
      // result field, not the status code, is what actually says whether
      // anything was deleted.
      const json = (await response.json()) as { result?: string };
      const deleted = json.result === "ok";
      if (!deleted) {
        logger.info(`deleteCloudinaryImage: Cloudinary result "${json.result}" for ${publicId}`);
      }
      return { deleted };
    } catch (error: unknown) {
      logger.error(`deleteCloudinaryImage: error for ${publicId}:`, error);
      return { deleted: false };
    }
  }
);
