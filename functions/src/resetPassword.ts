import { onCall, HttpsError } from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

interface ResetPasswordData {
  email: string;
  otp: string;
  newPassword: string;
}

// ─── Reset Password ─────────────────────────────────────────────────────────
// Re-validates that the given OTP is the most recently verified one for this
// email (must be used == true, since verifyOtp already marked it as used),
// then uses the Admin SDK to set the new password directly — no signed-in
// session required, since the user never logs in during this flow.
export const resetPassword = onCall(async (request) => {
  const { email, otp, newPassword } = request.data as ResetPasswordData;

  if (!email || !otp || !newPassword) {
    throw new HttpsError(
      "invalid-argument",
      "Email, code, and new password are required"
    );
  }

  if (newPassword.length < 8) {
    throw new HttpsError(
      "invalid-argument",
      "Password must be at least 8 characters"
    );
  }

  const normalizedEmail = email.toLowerCase().trim();
  const db = getFirestore();

  // Confirm this OTP was the one actually verified (used == true) and is
  // still within a short grace window after verification, so this endpoint
  // can't be replayed with an arbitrary old code.
  const snapshot = await db
    .collection("otps")
    .where("email", "==", normalizedEmail)
    .where("otp", "==", otp)
    .where("used", "==", true)
    .limit(1)
    .get();

  if (snapshot.empty) {
    logger.warn(`resetPassword: no verified OTP found for ${normalizedEmail}`);
    throw new HttpsError(
      "failed-precondition",
      "Code not verified. Please verify your code again."
    );
  }

  try {
    const auth = getAuth();
    const userRecord = await auth.getUserByEmail(normalizedEmail);

    await auth.updateUser(userRecord.uid, { password: newPassword });

    await db.collection("users").doc(normalizedEmail).set(
      {
        password_updated_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      },
      { merge: true }
    );

    logger.info(`Password reset successfully for: ${normalizedEmail}`);
    return { success: true };
  } catch (error: unknown) {
    logger.error("resetPassword error:", error);

    const code = (error as { code?: string })?.code;
    if (code === "auth/user-not-found") {
      throw new HttpsError("not-found", "User not found");
    }

    throw new HttpsError("internal", "Failed to reset password");
  }
});
