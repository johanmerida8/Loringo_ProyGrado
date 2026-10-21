// functions/src/listCloudinaryAvatars.ts
//
// Firebase Cloud Function (callable) that lists every image in Cloudinary's
// "avatars" folder via the admin "resources" endpoint.
//
// WHY THIS CAN'T BE A DIRECT CLIENT CALL (same reasoning as
// deleteCloudinaryImage.ts): the admin "resources" endpoint requires Basic
// auth with the API secret and isn't meant for direct browser/client use —
// moving it server-side keeps CLOUDINARY_API_SECRET out of the compiled
// client bundle.
//
// AUTH: like moderateImage.ts, reachable by unauthenticated callers —
// students (logged in via access code, not Firebase Auth) also need to open
// the avatar picker, e.g. from student_settings_screen.dart.
//
// TWO LOOKUP STYLES, TRIED IN ORDER: Cloudinary accounts created after the
// "Dynamic Folder Mode" rollout store an asset's folder as separate metadata
// from its Public ID — a file shown inside the "avatars" folder in the Media
// Library does NOT necessarily have a Public ID starting with "avatars/".
// Older/"Fixed Folder Mode" accounts DO use the folder as a literal Public ID
// prefix. Rather than guessing which mode this account uses, try the
// prefix-based query first (works for Fixed Folder Mode), and if that comes
// back empty, fall back to the by_asset_folder endpoint (Dynamic Folder Mode).

import { onCall, HttpsError } from "firebase-functions/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

const CLOUDINARY_API_KEY = defineSecret("CLOUDINARY_API_KEY");
const CLOUDINARY_API_SECRET = defineSecret("CLOUDINARY_API_SECRET");
const CLOUD_NAME = "dmflzlyzk"; // same constant as ImageService.cloudName

interface CloudinaryResource {
  public_id: string;
  secure_url: string;
}

/**
 * Fetches one page of Cloudinary admin resources from the given URL.
 * @param {string} url Full Cloudinary admin API URL to call.
 * @param {string} auth Base64-encoded "apiKey:apiSecret" Basic Auth value.
 * @return {Promise<CloudinaryResource[]>} The resources array, or [].
 */
async function fetchResources(
  url: string,
  auth: string
): Promise<CloudinaryResource[]> {
  const response = await fetch(url, { headers: { "Authorization": `Basic ${auth}` } });
  if (!response.ok) {
    logger.error(`listCloudinaryAvatars: HTTP ${response.status} for ${url}`);
    throw new HttpsError("internal", "Failed to list avatars");
  }
  const json = (await response.json()) as { resources?: CloudinaryResource[] };
  return json.resources ?? [];
}

export const listCloudinaryAvatars = onCall<
  unknown,
  Promise<{ avatars: { publicId: string; url: string }[] }>
>(
  { secrets: [CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET], maxInstances: 2 },
  async () => {
    const apiKey = CLOUDINARY_API_KEY.value();
    const apiSecret = CLOUDINARY_API_SECRET.value();
    const auth = Buffer.from(`${apiKey}:${apiSecret}`).toString("base64");
    const base = `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/resources`;

    let resources = await fetchResources(
      `${base}/image?type=upload&prefix=avatars/&max_results=500`,
      auth
    );
    logger.info(`listCloudinaryAvatars: prefix query returned ${resources.length}`);

    if (resources.length === 0) {
      resources = await fetchResources(
        `${base}/by_asset_folder?asset_folder=avatars&max_results=500`,
        auth
      );
      logger.info(`listCloudinaryAvatars: by_asset_folder query returned ${resources.length}`);
    }

    const avatars = resources
      .map((r) => ({ publicId: r.public_id, url: r.secure_url }))
      .sort((a, b) => a.publicId.localeCompare(b.publicId));

    return { avatars };
  }
);
