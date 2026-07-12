import FirebaseFirestore

/// Wire enums mirror functions/src/validation.ts exactly (10-TECH-PLAN.md §4).
/// If a case changes here, it changes there and in firestore.rules in the same breath.

enum SubmissionType: String, Codable, Sendable, Hashable, CaseIterable {
    case proverb = "Proverb"
    case poetry = "Poetry"
}

enum LanguageCode: String, Codable, Sendable, Hashable, CaseIterable {
    case somali = "so"
    case english = "en"
}

/// "attributed" on the wire, not the web's "shared" (10 §4 #5).
enum SubmissionOrigin: String, Codable, Sendable, Hashable, CaseIterable {
    case original
    case attributed
    case unknown
}

enum SubmissionStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case published
    case hidden
}

struct SubmissionSource: Codable, Sendable, Hashable {
    var name: String
    var url: String?
    var notes: String?
}

/// submissions/{id} — schema v2, frozen (10 §4). Callable-write-only except delete;
/// this type is a pure read model until M5 introduces the write-side draft.
struct Submission: Codable, Sendable, Hashable {
    @DocumentID var id: String?

    var authorUid: String
    /// Immutable once claimed, so denormalizing it here is permanently safe (10 §4 #3).
    /// Unlike displayName, which is mutable and therefore NOT denormalized.
    var authorUsername: String?

    var type: SubmissionType
    var language: LanguageCode
    var origin: SubmissionOrigin
    var status: SubmissionStatus

    /// Absent until the first setSubmissionStatus call (M10) — never present on
    /// freshly created or seeded submissions.
    var statusChangedAt: Date?
    var statusChangedBy: String?
    var statusReason: String?

    /// Required iff .poetry; nil for .proverb.
    var title: String?
    var text: String
    var meaning: String?
    var translation: String?
    var source: SubmissionSource?

    var createdAt: Date
    var updatedAt: Date?

    var voteUp: Int
    var voteDown: Int
    var voteScore: Int

    var searchIndex: String
    var searchKeywords: [String]

    /// Decrements on report resolution (10 §4 #4) — unlike the web's monotonic reportCount.
    var openReportCount: Int
}
