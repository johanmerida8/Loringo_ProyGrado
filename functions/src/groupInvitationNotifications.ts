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
import {
  callerOwnsGroup,
  encryptGroupCode,
  INVITATION_TTL_MS,
} from "./groupCode";

const ONESIGNAL_APP_ID = defineSecret("ONESIGNAL_APP_ID");
const ONESIGNAL_REST_API_KEY = defineSecret("ONESIGNAL_REST_API_KEY");
const GROUP_CODE_KEY = defineSecret("GROUP_CODE_KEY");

interface SendGroupInvitationData {
  parentEmail: string;
  groupId: string;
  groupName: string;
}

export const sendGroupInvitationNotification = onCall(
  { secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY, GROUP_CODE_KEY] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }
    const { parentEmail, groupId, groupName } =
      request.data as SendGroupInvitationData;

    if (!parentEmail || !groupId || !groupName) {
      throw new HttpsError("invalid-argument", "Missing required fields");
    }

    const db = getFirestore();

    // The code never travels from the client and is never stored in the
    // clear: the notification carries the group's own encrypted code, which
    // only revealInvitationGroupCode can decrypt, for the invited parent.
    const groupSnap = await db.collection("teacherGroups").doc(groupId).get();
    if (!groupSnap.exists) {
      throw new HttpsError("not-found", "Group not found.");
    }
    const groupData = groupSnap.data() ?? {};
    if (!callerOwnsGroup(request.auth.uid, groupData.teacherId)) {
      throw new HttpsError(
        "permission-denied",
        "Only the owning teacher can invite to this group."
      );
    }
    let groupCodeEncrypted = groupData.groupCodeEncrypted as string | undefined;
    if (!groupCodeEncrypted && typeof groupData.groupCode === "string") {
      // Legacy group still holding its code in plaintext.
      groupCodeEncrypted = encryptGroupCode(
        groupData.groupCode,
        GROUP_CODE_KEY.value()
      );
    }
    if (!groupCodeEncrypted) {
      throw new HttpsError("failed-precondition", "Group has no code.");
    }
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
      data: { groupId, groupName, groupCodeEncrypted },
      isRead: false,
      createdAt: Timestamp.now(),
      expiresAt: Timestamp.fromMillis(Date.now() + INVITATION_TTL_MS),
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
