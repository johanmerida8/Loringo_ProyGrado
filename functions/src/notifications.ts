import { onCall, HttpsError } from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";

const ONESIGNAL_APP_ID = defineSecret("ONESIGNAL_APP_ID");
const ONESIGNAL_REST_API_KEY = defineSecret("ONESIGNAL_REST_API_KEY");

interface SendNotificationData {
  userId: string;
  title: string;
  body: string;
}

export const sendNotification = onCall(
  { secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY] },
  async (request) => {
    const { userId, title, body } = request.data as SendNotificationData;

    if (!userId || !title || !body) {
      throw new HttpsError("invalid-argument", "Missing required fields");
    }

    logger.info(`Sending notification to user: ${userId}`);

    const response = await fetch(
      "https://onesignal.com/api/v1/notifications",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Basic ${ONESIGNAL_REST_API_KEY.value()}`,
        },
        body: JSON.stringify({
          app_id: ONESIGNAL_APP_ID.value(),
          include_external_user_ids: [userId],
          headings: { en: title },
          contents: { en: body },
        }),
      }
    );

    const result = await response.json();

    if (response.status !== 200) {
      logger.error("OneSignal error:", result);
      throw new HttpsError("internal", "Failed to send notification");
    }

    logger.info("Notification sent successfully");
    return { success: true };
  }
);
