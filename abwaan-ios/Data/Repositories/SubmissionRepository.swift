import FirebaseFirestore

/// Filter + sort for the public archive feed. Every field maps to a real query predicate
/// (10 §7, Option 2 — the scope bar tells the truth), backed by the composite indexes in
/// firebase/firestore.indexes.json.
struct SubmissionFilter: Sendable, Hashable {
    enum Sort: Sendable, Hashable {
        case newest    // createdAt DESC
        case topRated  // voteScore DESC
    }

    var type: SubmissionType?      // nil = all types
    var language: LanguageCode?    // nil = all languages
    var sort: Sort

    init(type: SubmissionType? = nil, language: LanguageCode? = nil, sort: Sort = .newest) {
        self.type = type
        self.language = language
        self.sort = sort
    }
}

/// Reads over the `submissions` collection. Writes go through callables (createSubmission,
/// updateSubmission, voteSubmission, setSubmissionStatus) or direct delete, each arriving
/// with its own milestone — not here. This protocol is the seam M2 (archive) and M3
/// (detail + public profile) read through; no Firebase type appears in its signatures.
protocol SubmissionRepository: Sendable {
    /// A single submission by id, or nil if it does not exist. Rules gate readability
    /// (published, or owner/admin); a denied read surfaces as a thrown error.
    func submission(id: String) async throws -> Submission?

    /// A page of **published** submissions matching `filter`, resuming after `cursor`.
    func submissions(
        matching filter: SubmissionFilter,
        after cursor: PageCursor?,
        limit: Int
    ) async throws -> Page<Submission>

    /// A page of one author's submissions, newest first. `includeHidden` is for the owner's
    /// own Desk (M7); public profiles (M3) pass `false`.
    func submissions(
        byAuthor uid: String,
        includeHidden: Bool,
        after cursor: PageCursor?,
        limit: Int
    ) async throws -> Page<Submission>

    /// Count of an author's published submissions via a `count()` aggregation — the
    /// replacement for the deleted profile counters (13 §A1). One aggregation read.
    func publishedCount(authorUid uid: String) async throws -> Int
}

/// Live Firestore implementation. A stateless value: it holds no Firebase handle (it reads
/// `Firestore.firestore()` per call), so it is trivially `Sendable`. `DocumentSnapshot` →
/// `Submission` mapping happens here, at the boundary, via `data(as:)`.
struct FirestoreSubmissionRepository: SubmissionRepository {
    private var collection: CollectionReference {
        Firestore.firestore().collection("submissions")
    }

    func submission(id: String) async throws -> Submission? {
        let snapshot = try await collection.document(id).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: Submission.self)
    }

    func submissions(
        matching filter: SubmissionFilter,
        after cursor: PageCursor?,
        limit: Int
    ) async throws -> Page<Submission> {
        var query: Query = collection
            .whereField("status", isEqualTo: SubmissionStatus.published.rawValue)
        if let type = filter.type {
            query = query.whereField("type", isEqualTo: type.rawValue)
        }
        if let language = filter.language {
            query = query.whereField("language", isEqualTo: language.rawValue)
        }
        switch filter.sort {
        case .newest:
            query = query.order(by: "createdAt", descending: true)
        case .topRated:
            query = query.order(by: "voteScore", descending: true)
        }
        return try await fetchPage(query, after: cursor, limit: limit)
    }

    func submissions(
        byAuthor uid: String,
        includeHidden: Bool,
        after cursor: PageCursor?,
        limit: Int
    ) async throws -> Page<Submission> {
        var query: Query = collection.whereField("authorUid", isEqualTo: uid)
        if !includeHidden {
            query = query.whereField("status", isEqualTo: SubmissionStatus.published.rawValue)
        }
        query = query.order(by: "createdAt", descending: true)
        return try await fetchPage(query, after: cursor, limit: limit)
    }

    func publishedCount(authorUid uid: String) async throws -> Int {
        let query = collection
            .whereField("authorUid", isEqualTo: uid)
            .whereField("status", isEqualTo: SubmissionStatus.published.rawValue)
        let snapshot = try await query.count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    private func fetchPage(
        _ query: Query,
        after cursor: PageCursor?,
        limit: Int
    ) async throws -> Page<Submission> {
        var query = query.limit(to: limit)
        if let cursor, let last = cursor.boxed as? DocumentSnapshot {
            query = query.start(afterDocument: last)
        }
        let snapshot = try await query.getDocuments()
        let items = try snapshot.documents.map { try $0.data(as: Submission.self) }
        // A cursor iff the page came back full — matches the fake's semantics exactly.
        let nextCursor = items.count == limit ? snapshot.documents.last.map(PageCursor.init) : nil
        return Page(items: items, cursor: nextCursor)
    }
}
