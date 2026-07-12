import Foundation

/// In-memory repository fakes for tests and SwiftUI previews (10 §2). They replicate the
/// live Firestore repositories' filtering, sorting, and pagination semantics so a test that
/// passes against the fake is asserting the contract the Firestore implementation must also
/// meet. No Firebase dependency — these run anywhere, no emulator.
///
/// Actors: the mutable dictionary state is isolated, so the fakes are `Sendable` and safe to
/// share across the async repository boundary.

actor InMemorySubmissionRepository: SubmissionRepository {
    private var byId: [String: Submission]

    init(_ submissions: [Submission] = []) {
        var byId: [String: Submission] = [:]
        for submission in submissions {
            if let id = submission.id { byId[id] = submission }
        }
        self.byId = byId
    }

    /// Test/preview affordance — insert or replace a submission.
    func upsert(_ submission: Submission) {
        if let id = submission.id { byId[id] = submission }
    }

    func submission(id: String) async throws -> Submission? {
        byId[id]
    }

    func submissions(
        matching filter: SubmissionFilter,
        after cursor: PageCursor?,
        limit: Int
    ) async throws -> Page<Submission> {
        var results = byId.values.filter { $0.status == .published }
        if let type = filter.type { results = results.filter { $0.type == type } }
        if let language = filter.language { results = results.filter { $0.language == language } }
        sort(&results, by: filter.sort)
        return paginate(results, after: cursor, limit: limit)
    }

    func submissions(
        byAuthor uid: String,
        includeHidden: Bool,
        after cursor: PageCursor?,
        limit: Int
    ) async throws -> Page<Submission> {
        var results = byId.values.filter { $0.authorUid == uid }
        if !includeHidden { results = results.filter { $0.status == .published } }
        sort(&results, by: .newest)
        return paginate(results, after: cursor, limit: limit)
    }

    func publishedCount(authorUid uid: String) async throws -> Int {
        byId.values.filter { $0.authorUid == uid && $0.status == .published }.count
    }

    // MARK: - query mechanics (mirrors Firestore)

    private func sort(_ submissions: inout [Submission], by sort: SubmissionFilter.Sort) {
        switch sort {
        case .newest:
            submissions.sort { lhs, rhs in
                lhs.createdAt != rhs.createdAt
                    ? lhs.createdAt > rhs.createdAt
                    : (lhs.id ?? "") > (rhs.id ?? "") // __name__ tiebreaker, matching DESC primary
            }
        case .topRated:
            submissions.sort { lhs, rhs in
                lhs.voteScore != rhs.voteScore
                    ? lhs.voteScore > rhs.voteScore
                    : (lhs.id ?? "") > (rhs.id ?? "")
            }
        }
    }

    private func paginate(
        _ sorted: [Submission],
        after cursor: PageCursor?,
        limit: Int
    ) -> Page<Submission> {
        let start = (cursor?.boxed as? Int) ?? 0
        let clampedStart = min(max(start, 0), sorted.count)
        let end = min(clampedStart + limit, sorted.count)
        let items = Array(sorted[clampedStart..<end])
        // Cursor iff the page came back full — matches FirestoreSubmissionRepository exactly.
        let nextCursor = items.count == limit ? PageCursor(end) : nil
        return Page(items: items, cursor: nextCursor)
    }
}

actor InMemoryProfileRepository: ProfileRepository {
    private var byUid: [String: Profile]

    init(_ profiles: [Profile] = []) {
        var byUid: [String: Profile] = [:]
        for profile in profiles {
            if let id = profile.id { byUid[id] = profile }
        }
        self.byUid = byUid
    }

    /// Test/preview affordance — insert or replace a profile.
    func upsert(_ profile: Profile) {
        if let id = profile.id { byUid[id] = profile }
    }

    func profile(uid: String) async throws -> Profile? {
        byUid[uid]
    }
}
