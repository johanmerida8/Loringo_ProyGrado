import { onCall, HttpsError } from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { Resend } from "resend";

const RESEND_API_KEY = defineSecret("RESEND_API_KEY");

interface SendOtpData {
  email: string;
}

interface VerifyOtpData {
  email: string;
  otp: string;
}

// ─── Send OTP ─────────────────────────────────────────────────────────────
// Uses the `otps` collection (one auto-ID document per send, kept as a
// history/log — same shape as the old Supabase flow), instead of a single
// overwritten doc per email.
export const sendOtpEmail = onCall(
  { secrets: [RESEND_API_KEY] },
  async (request) => {
    const { email } = request.data as SendOtpData;

    if (!email) {
      throw new HttpsError("invalid-argument", "Email is required");
    }

    const normalizedEmail = email.toLowerCase().trim();
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 min

    logger.info(`Generating OTP for: ${normalizedEmail}`);

    const db = getFirestore();

    // Mark any previous unused OTPs for this email as used, so only the
    // newest code is valid — mirrors the old Supabase/Firestore behavior.
    const oldOtps = await db
      .collection("otps")
      .where("email", "==", normalizedEmail)
      .where("used", "==", false)
      .get();

    const batch = db.batch();
    oldOtps.docs.forEach((doc) => {
      batch.update(doc.ref, { used: true });
    });
    await batch.commit();

    // Add the new OTP as a fresh document (auto-ID), keeping history.
    await db.collection("otps").add({
      email: normalizedEmail,
      otp,
      used: false,
      expiresAt: Timestamp.fromDate(expiresAt),
      createdAt: FieldValue.serverTimestamp(),
    });

    const resend = new Resend(RESEND_API_KEY.value());

    const { error } = await resend.emails.send({
      from: "Loringo <noreply@mail.loringoapp.com>",
      to: [normalizedEmail],
      subject: "Your verification code",
      html: `<h1>Your code is: ${otp}</h1><p>Valid for 15 minutes.</p>`,
    });

    if (error) {
      logger.error("Resend error:", error);
      throw new HttpsError("internal", "Failed to send email");
    }

    logger.info("OTP email sent successfully");
    return { success: true };
  }
);

// ─── Verify OTP ───────────────────────────────────────────────────────────
// Queries `otps` by email + code + used==false + expiresAt > now,
// same logic as the old client-side Supabase/Firestore version, just
// moved server-side so the code itself never has to be trusted from
// a client-readable source.
export const verifyOtp = onCall(async (request) => {
  const { email, otp } = request.data as VerifyOtpData;

  if (!email || !otp) {
    throw new HttpsError("invalid-argument", "Email and code are required");
  }

  const normalizedEmail = email.toLowerCase().trim();
  const db = getFirestore();

  const snapshot = await db
    .collection("otps")
    .where("email", "==", normalizedEmail)
    .where("otp", "==", otp)
    .where("used", "==", false)
    .where("expiresAt", ">", Timestamp.now())
    .limit(1)
    .get();

  if (snapshot.empty) {
    logger.info(`OTP verification failed for: ${normalizedEmail}`);
    throw new HttpsError("invalid-argument", "Invalid or expired code");
  }

  await snapshot.docs[0].ref.update({ used: true });

  logger.info(`OTP verified for: ${normalizedEmail}`);
  return { success: true };
});
