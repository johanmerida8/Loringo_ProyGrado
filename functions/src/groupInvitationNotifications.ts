// functions/src/groupInvitationNotifications.ts
//
// HTTPS callable the teacher's app invokes from invite_student_modal.dart
// when a teacher invites a parent (by email) to join their group.
// Previously this whole flow — looking up the parent by email, writing
// the Firestore `notifications` doc, and calling
// OneSignalNotificationService.sendNotification — lived inline in that
// Dart widget, duplicating the exact same pattern
// notification_service.dart used for report notifications. This
// consolidates both onto one server-side shape: the callable resolves
// the parent itself (the client only sends the email it was given, not
// a pre-resolved parentId), so a "no parent found" failure surfaces the
// same way a report notification's missing-parent case does.

import { onCall, HttpsError } from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

const ONESIGNAL_APP_ID = defineSecret("ONESIGNAL_APP_ID");
const ONESIGNAL_REST_API_KEY = defineSecret("ONESIGNAL_REST_API_KEY");

interface SendGroupInvitationData {
  parentEmail: string;
  groupId: string;
  groupName: string;
  groupCode: string;
}

export const sendGroupInvitationNotification = onCall(
  { secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY] },
  async (request) => {
    const { parentEmail, groupId, groupName, groupCode } =
      request.data as SendGroupInvitationData;

    if (!parentEmail || !groupId || !groupName || !groupCode) {
      throw new HttpsError("invalid-argument", "Missing required fields");
    }

    const db = getFirestore();
    const userSnap = await db
      .collection("users")
      .where("email", "==", parentEmail)
      .where("role", "==", "parent")
      .limit(1)
      .get();

    if (userSnap.empty) {
      // Same user-facing wording invite_student_modal.dart already
      // shows today, now originating from the callable's error instead
      // of a client-side query the caller did itself.
      throw new HttpsError("not-found", "No parent found with that email");
    }

    const parentId = userSnap.docs[0].id;
    const title = "Group Invitation";
    const message = `You have been invited to the group ${groupName}.`;

    await db.collection("notifications").add({
      userId: parentId,
      type: "group_invitation",
      title,
      message,
      data: { groupId, groupName, groupCode },
      isRead: false,
      createdAt: Timestamp.now(),
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
      return { success: true, pushDelivered: false };
    }

    logger.info(`sendGroupInvitationNotification: invited parent ${parentId} to group ${groupId}`);
    return { success: true, pushDelivered: true };
  }
);
