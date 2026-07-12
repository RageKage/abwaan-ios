import FirebaseFirestore

/// submissions/{id}/votes/{uid} — written by the voteSubmission callable (M6), not
/// a direct client write. Owner reads only their own vote doc (firestore.rules).
struct Vote: Codable, Sendable, Hashable {
    /// == the voter's uid.
    @DocumentID var id: String?

    /// -1, 0, or 1. Tapping the same arrow twice sends 0, which deletes the doc
    /// rather than storing it (10 §5) — a decoded Vote is always -1 or 1 in practice.
    var value: Int
    var createdAt: Date
    var updatedAt: Date?
}

/// privateUsers/{uid}/favorites/{submissionId} — DIRECT client write (queues offline).
/// The rules assert savedAt == request.time, so @ServerTimestamp fills it on encode
/// and the client never has to construct a timestamp itself.
struct Favorite: Codable, Sendable, Hashable {
    /// == the favorited submission's id.
    @DocumentID var id: String?

    @ServerTimestamp var savedAt: Date?
}
