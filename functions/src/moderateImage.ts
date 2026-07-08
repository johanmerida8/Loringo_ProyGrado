import { onCall, HttpsError } from "firebase-functions/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

const visionApiKey = defineSecret("GOOGLE_VISION_API_KEY");

interface ModerateImageData {
  imageBase64: string; // imagen ya codificada en base64, sin el prefijo data:...
}

interface SafeSearchAnnotation {
  adult?: string;
  violence?: string;
  racy?: string;
}

// ─── Moderate Image ─────────────────────────────────────────────────────────
// Recibe una imagen en base64 desde el cliente y la analiza vía Google Cloud
// Vision SafeSearch. La API key nunca llega al cliente — vive como secret de
// Cloud Functions. Solo VERY_LIKELY en adult/violence/racy bloquea la imagen,
// ya que LIKELY es demasiado agresivo para contenido ilustrado/infantil.
export const moderateImage = onCall(
  { secrets: [visionApiKey] },
  async (request) => {
    const { imageBase64 } = request.data as ModerateImageData;

    if (!imageBase64) {
      throw new HttpsError("invalid-argument", "imageBase64 is required");
    }

    const apiKey = visionApiKey.value();

    try {
      const response = await fetch(
        `https://vision.googleapis.com/v1/images:annotate?key=${apiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            requests: [
              {
                image: { content: imageBase64 },
                features: [{ type: "SAFE_SEARCH_DETECTION" }],
              },
            ],
          }),
        }
      );

      if (!response.ok) {
        logger.error(`moderateImage: Vision API HTTP ${response.status}`);
        // Fail closed: si Vision API falla, se rechaza la imagen en vez de
        // dejarla pasar sin verificar.
        return { safe: false, reason: "MODERATION_SERVICE_ERROR" };
      }

      const json = (await response.json()) as {
        responses: { safeSearchAnnotation?: SafeSearchAnnotation }[];
      };

      const safeSearch = json.responses?.[0]?.safeSearchAnnotation ?? {};

      const flaggedCategory = (["adult", "violence", "racy"] as const).find(
        (key) => safeSearch[key] === "VERY_LIKELY"
      );

      if (flaggedCategory) {
        logger.info(`moderateImage: flagged for ${flaggedCategory}`);
        return { safe: false, reason: "REJECT_INAPPROPRIATE_IMAGE" };
      }

      return { safe: true };
    } catch (error: unknown) {
      logger.error("moderateImage error:", error);
      // Fail closed también en errores de red/parseo inesperados.
      return { safe: false, reason: "MODERATION_SERVICE_ERROR" };
    }
  }
);
