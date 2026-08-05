// functions/src/reportNotifications.ts
//
// HTTPS callable the teacher's app invokes from the "Send Report to
// Parent" button (unit_quiz_review_screen.dart, after Database
// .saveReportOnly writes the report doc itself — that write stays
// client-side since it's ordinary app business logic, not a
// notification concern; only the "who to notify and how" part moves
// here). Supersedes lib/services/notifications/notification_service.dart
// entirely: this function does the parentId lookup, the Firestore
// `notifications` doc write, and the OneSignal push in one place,
// server-side, instead of three separate client-side steps.

import { onCall, HttpsError } from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

const ONESIGNAL_APP_ID = defineSecret("ONESIGNAL_APP_ID");
const ONESIGNAL_REST_API_KEY = defineSecret("ONESIGNAL_REST_API_KEY");

interface SendReportNotificationData {
  studentId: string;
  studentName: string;
  unitTitle: string;
}

export const sendReportNotification = onCall(
  { secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY] },
  async (request) => {
    const { studentId, studentName, unitTitle } =
      request.data as SendReportNotificationData;

    if (!studentId || !studentName || !unitTitle) {
      throw new HttpsError("invalid-argument", "Missing required fields");
    }

    const db = getFirestore();
    const studentDoc = await db.collection("students").doc(studentId).get();
    const parentId = studentDoc.data()?.parentId as string | undefined;

    if (!parentId) {
      logger.info(`sendReportNotification: no parentId for student ${studentId}`);
      // Not an error — a student without a linked parent just has
      // nothing to notify, same as the client-side version's silent
      // early return did.
      return { success: false, reason: "no-parent" };
    }

    const title = "New Report Available";
    const message = `${studentName} completed "${unitTitle}".`;

    await db.collection("notifications").add({
      userId: parentId,
      type: "quiz_report",
      title,
      message,
      isRead: false,
      createdAt: Timestamp.now(),
      data: { studentId, studentName, unitTitle },
    });

    const response = await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Basic ${ONESIGNAL_REST_API_KEY.value()}`,
      },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID.value(),
        include_external_user_ids: [parentId],
        headings: { en: title },
        contents: { en: message },
      }),
    });

    if (response.status !== 200) {
      const result = await response.json();
      logger.error(`OneSignal error for parent ${parentId}:`, result);
      // Swallowed, not thrown: the Firestore notifications-history doc
      // above is already written, so the report is still visible in
      // the parent's in-app bell even if the push itself fails.
      return { success: true, pushDelivered: false };
    }

    logger.info(`sendReportNotification: notified parent ${parentId}`);
    return { success: true, pushDelivered: true };
  }
);
