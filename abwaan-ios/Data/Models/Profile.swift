import FirebaseFirestore

/// profiles/{uid} — world-readable (10 §4). Created only by the bootstrapProfile
/// callable (13 §A2); the client edits displayName/bio, never creates or deletes.
///
/// No counters (13 §A1 — use count() aggregation instead) and no lastSeenAt
/// (13 §A6 — a presence leak with nothing reading it). Both were deliberately cut.
struct Profile: Codable, Sendable, Hashable {
    /// == the Firebase Auth uid.
    @DocumentID var id: String?

    var displayName: String
    /// nil until claimed via claimUsername; immutable once set.
    var username: String?
    var bio: String
    /// Provider CDN URL (e.g. Google). Never uploaded/hosted by this app (10 §3).
    var photoURL: String?
    var createdAt: Date
}

/// privateUsers/{uid} — owner-read-only (10 §4). Created only by bootstrapProfile;
/// the client edits blockedUids only (13 §A7).
struct PrivateUser: Codable, Sendable, Hashable {
    /// == the Firebase Auth uid.
    @DocumentID var id: String?

    var email: String
    var providerId: String?
    /// Refreshed by bootstrapProfile on every sign-in (10 §4 #9).
    var lastLoginAt: Date
    /// Rule-capped at 500 (13 §A7). Arrives free with a doc the session already reads.
    var blockedUids: [String]
}
