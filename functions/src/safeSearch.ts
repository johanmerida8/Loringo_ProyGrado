// functions/src/safeSearch.ts
//
// Llama a Google Cloud Vision (SafeSearch + etiquetas + objetos) y aplica la
// política del modo en vigor (moderationPolicy.ts). Lo usa uploadModeratedImage,
// la única función que sube imágenes. No es una Cloud Function: la API key
// nunca llega al cliente y el modo lo decide el servidor
// (appSettings/imageModeration), nunca el cliente.

import * as logger from "firebase-functions/logger";
import {
  ModerationMode,
  SafeSearchAnnotation,
  SafeSearchVerdict,
  VisionLabel,
  VisionObject,
  evaluateContent,
  evaluateSafeSearch,
} from "./moderationPolicy";

export type SafeSearchResult = SafeSearchVerdict;

/**
 * Corre Vision SafeSearch sobre una imagen y aplica la política de [mode]
 * (moderationPolicy.ts). Lo usa uploadModeratedImage.
 * Fail closed: cualquier error, respuesta incompleta o categoría desconocida
 * devuelve safe: false.
 *
 * @param {string} imageBase64 Imagen en base64, sin prefijo data:.
 * @param {string} apiKey Valor del secret GOOGLE_VISION_API_KEY.
 * @param {ModerationMode} mode Modo en vigor, decidido por el servidor.
 * @param {string} label Texto opcional para los logs (p. ej. el nombre del archivo).
 * @return {Promise<SafeSearchResult>} Si la imagen es segura o por qué no.
 */
export async function checkSafeSearch(
  imageBase64: string,
  apiKey: string,
  mode: ModerationMode,
  label = ""
): Promise<SafeSearchResult> {
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
              features: [
                { type: "SAFE_SEARCH_DETECTION" },
                // Labels and objects catch what SafeSearch doesn't rate:
                // weapons, alcohol, tobacco, drugs (moderationPolicy.ts).
                { type: "LABEL_DETECTION", maxResults: 20 },
                { type: "OBJECT_LOCALIZATION", maxResults: 15 },
              ],
            },
          ],
        }),
      }
    );

    if (!response.ok) {
      logger.error(`safeSearch: Vision API HTTP ${response.status}`);
      // Fail closed: si Vision API falla, se rechaza la imagen en vez de
      // dejarla pasar sin verificar.
      return { safe: false, reason: "MODERATION_SERVICE_ERROR" };
    }

    const json = (await response.json()) as {
      responses?: {
        safeSearchAnnotation?: SafeSearchAnnotation;
        labelAnnotations?: VisionLabel[];
        localizedObjectAnnotations?: VisionObject[];
        error?: { code?: number; message?: string };
      }[];
    };

    const first = json.responses?.[0];
    const safeSearch = first?.safeSearchAnnotation;

    // Vision can answer HTTP 200 with a per-image error (or nothing at all)
    // instead of an annotation. That must never count as "safe".
    if (first?.error || !safeSearch) {
      logger.error("safeSearch: Vision returned no SafeSearch annotation", {
        error: first?.error,
      });
      return { safe: false, reason: "MODERATION_SERVICE_ERROR" };
    }

    // The five likelihoods + the mode in force, logged for every image so the
    // thresholds can be tuned with real data.
    logger.info("safeSearch: SafeSearch", {
      mode,
      file: label || undefined,
      adult: safeSearch.adult,
      medical: safeSearch.medical,
      spoof: safeSearch.spoof,
      violence: safeSearch.violence,
      racy: safeSearch.racy,
      labels: (first.labelAnnotations ?? [])
        .slice(0, 10)
        .map((l) => `${l.description}:${(l.score ?? 0).toFixed(2)}`),
      objects: (first.localizedObjectAnnotations ?? [])
        .map((o) => `${o.name}:${(o.score ?? 0).toFixed(2)}`),
    });

    // SafeSearch first (it also fails closed on unrated categories), then
    // the labels / objects.
    const safeSearchVerdict = evaluateSafeSearch(safeSearch, mode);
    const verdict = safeSearchVerdict.safe ?
      evaluateContent(first.labelAnnotations, first.localizedObjectAnnotations, mode) :
      safeSearchVerdict;
    if (!verdict.safe) {
      logger.info(
        `safeSearch: ${verdict.reason} (${mode} mode, ${verdict.category ?? "n/a"})`
      );
    }
    return verdict;
  } catch (error: unknown) {
    logger.error("safeSearch error:", error);
    // Fail closed también en errores de red/parseo inesperados.
    return { safe: false, reason: "MODERATION_SERVICE_ERROR" };
  }
}
