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
setGlobalOptions({ maxInstances: 10 });

export * from "./notifications";
export * from "./email";
export * from "./resetPassword";
export * from "./moderateImage";
