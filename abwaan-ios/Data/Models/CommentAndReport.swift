import FirebaseFirestore

/// submissions/{id}/comments/{autoId} — DIRECT client write (queues offline). Rules
/// gate creation on a real username (13 §A8) and assert createdAt == request.time.
struct Comment: Codable, Sendable, Hashable {
    @DocumentID var id: String?

    var authorUid: String
    var authorUsername: String?
    var body: String
    @ServerTimestamp var createdAt: Date?
}

enum ReportReason: String, Codable, Sendable, Hashable, CaseIterable {
    case spam
    case abuse
    case plagiarism
    case inaccurate
    case other
}

/// "open" on create only, closed by resolveReport (M10) into one of the other two —
/// action names ("dismiss"/"resolve") per 12-ROADMAP.md M10.
enum ReportStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case open
    case dismissed
    case resolved
}

/// submissions/{id}/reports/{reporterUid} — DIRECT client write on create (queues
/// offline), one per reporter (rules' !exists() guard). Resolution is the
/// resolveReport callable (M10); update/delete are closed to the client. Exact key
/// set copied from the web's proven ruleset (11-RISKS.md R8) — every field below is
/// required, none is incidental.
struct Report: Codable, Sendable, Hashable {
    /// == the reporter's uid.
    @DocumentID var id: String?

    var submissionId: String
    var submissionType: SubmissionType
    var submissionTitle: String
    var submissionAuthorUid: String
    var submissionAuthorUsername: String?

    var reporterUid: String
    var reporterUsername: String?

    var reason: ReportReason
    var details: String?
    var status: ReportStatus

    @ServerTimestamp var createdAt: Date?
    var reviewedAt: Date?
    var reviewedBy: String?
}
