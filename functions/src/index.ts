/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import { setGlobalOptions } from "firebase-functions";
import { initializeApp } from "firebase-admin/app";

initializeApp();

// For cost control, set the maximum number of containers running at once.
// Kept low across ~20 functions (mostly Firestore triggers/crons, not hot
// HTTP paths) to stay under the per-region Cloud Run CPU quota at deploy time.
setGlobalOptions({ maxInstances: 3 });

export * from "./notifications";
export * from "./email";
export * from "./resetPassword";
export * from "./moderateImage";
export * from "./deleteCloudinaryImage";
export * from "./listCloudinaryAvatars";
export * from "./groupCode";
export * from "./generateReadingAudio";
export * from "./generateTaskAudio";
export * from "./prewarmTtsCache";
export * from "./processTtsUploadQueue";
export * from "./cleanupOrphanedTtsCache";
export * from "./scheduledNotifications";
export * from "./activityCreatedNotifications";
export * from "./activityUpdatedNotifications";
export * from "./notifyOverdueActivities";
export * from "./notifyStudentPerformance";
export * from "./reportNotifications";
export * from "./groupInvitationNotifications";
export * from "./resetLeagueSeasons";
