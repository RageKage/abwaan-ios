/**
 * Abwaan Cloud Functions — v2 only.
 *
 * M1 wires exactly ONE callable: bootstrapProfile (13 §A2). The feature callables
 * (claimUsername, createSubmission, updateSubmission, voteSubmission,
 * setSubmissionStatus, resolveReport, deleteAccount) and the triggers
 * (onReportCreate, onSubmissionDelete) belong to their own milestones and are not
 * written here. The shared helpers they will use — validation.ts, search.ts —
 * already exist so the server-side constraints are pinned early and the seeder can
 * reuse them.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

initializeApp();
const db = getFirestore();

interface BootstrapProfileResult {
  uid: string;
  displayName: string;
  username: string | null;
  bio: string;
  photoURL: string | null;
  createdAt: number | null; // epoch millis; the client also holds a live snapshot
}

/**
 * Idempotent profile bootstrap. The client invokes this once after every sign-in when
 * SessionModel sees no profile document (13 §A2). It:
 *   - creates profiles/{uid} and privateUsers/{uid} if missing
 *   - ALWAYS writes providerId and photoURL (null when absent) and bio: "" so the
 *     rules' update-pins have values to echo (client displayName/bio and blockedUids
 *     edits pin those fields)
 *   - refreshes privateUsers.lastLoginAt on every call, making that field honest
 *   - never sets username (claimed later via the claimUsername callable) — so a fresh
 *     profile lands the session in the needsUsername state
 *   - never falls back to the email for displayName: profiles are world-readable and
 *     the email is private (13 §A6). displayName = token.name ?? "".
 */
export const bootstrapProfile = onCall<void, Promise<BootstrapProfileResult>>(
  async (request): Promise<BootstrapProfileResult> => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const uid = auth.uid;
    const token = auth.token;

    const displayName = typeof token.name === "string" ? token.name : "";
    const email = typeof token.email === "string" ? token.email : "";
    const photoURL = typeof token.picture === "string" ? token.picture : null;
    const providerId =
      typeof token.firebase?.sign_in_provider === "string"
        ? token.firebase.sign_in_provider
        : null;

    const profileRef = db.doc(`profiles/${uid}`);
    const privateRef = db.doc(`privateUsers/${uid}`);

    await db.runTransaction(async (tx) => {
      const [profileSnap, privateSnap] = await Promise.all([
        tx.get(profileRef),
        tx.get(privateRef),
      ]);

      const now = FieldValue.serverTimestamp();

      if (!profileSnap.exists) {
        tx.set(profileRef, {
          displayName,
          username: null,
          bio: "",
          photoURL,
          createdAt: now,
        });
      }

      if (!privateSnap.exists) {
        tx.set(privateRef, {
          email,
          providerId,
          lastLoginAt: now,
          blockedUids: [],
        });
      } else {
        tx.update(privateRef, { lastLoginAt: now });
      }
    });

    const profileSnap = await profileRef.get();
    const data = profileSnap.data() ?? {};
    const createdAt = data.createdAt;

    logger.info("bootstrapProfile completed", {
      uid,
      providerId,
      created: !("username" in data) ? true : undefined,
    });

    return {
      uid,
      displayName: typeof data.displayName === "string" ? data.displayName : "",
      username: typeof data.username === "string" ? data.username : null,
      bio: typeof data.bio === "string" ? data.bio : "",
      photoURL: typeof data.photoURL === "string" ? data.photoURL : null,
      createdAt: createdAt instanceof Timestamp ? createdAt.toMillis() : null,
    };
  },
);
