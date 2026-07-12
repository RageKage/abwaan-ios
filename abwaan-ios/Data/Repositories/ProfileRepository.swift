import FirebaseFirestore

/// Reads over the world-readable `profiles` collection. Profile creation is the
/// bootstrapProfile callable (13 §A2) and edits are direct client writes (displayName/bio)
/// — both arrive at M4 with their milestone. M1/M3 need only the read seam: fetch a
/// profile by uid (public profile header, author resolution). Username availability and
/// the live self-profile snapshot listener belong to M4 and are deferred with it.
protocol ProfileRepository: Sendable {
    /// A profile by uid, or nil if none exists yet (e.g. a tombstoned/deleted author).
    func profile(uid: String) async throws -> Profile?
}

/// Live Firestore implementation. Stateless value, `Sendable`; maps `DocumentSnapshot` →
/// `Profile` at the boundary.
struct FirestoreProfileRepository: ProfileRepository {
    func profile(uid: String) async throws -> Profile? {
        let snapshot = try await Firestore.firestore()
            .collection("profiles")
            .document(uid)
            .getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: Profile.self)
    }
}
