import Testing
import Foundation
@testable import abwaan_ios

/// Fake-backed repository tests (M1 batch 5). They exercise the read/filter/sort/paginate
/// contract against the in-memory fakes — no emulator, no Firebase. Because the fakes are
/// written to mirror the Firestore implementations' semantics exactly, a green test here is
/// the contract FirestoreSubmissionRepository must also satisfy; the live implementations
/// are exercised end-to-end against seeded data starting in M2.
struct RepositoryTests {

    // MARK: - fixtures

    private func makeSubmission(
        id: String,
        authorUid: String = "bob",
        type: SubmissionType = .proverb,
        language: LanguageCode = .somali,
        status: SubmissionStatus = .published,
        createdAt: Date,
        voteScore: Int = 0
    ) -> Submission {
        Submission(
            id: id,
            authorUid: authorUid,
            authorUsername: authorUid,
            type: type,
            language: language,
            origin: .original,
            status: status,
            statusChangedAt: nil,
            statusChangedBy: nil,
            statusReason: nil,
            title: type == .poetry ? "Title \(id)" : nil,
            text: "Text \(id)",
            meaning: nil,
            translation: nil,
            source: nil,
            createdAt: createdAt,
            updatedAt: nil,
            voteUp: max(voteScore, 0),
            voteDown: 0,
            voteScore: voteScore,
            searchIndex: id,
            searchKeywords: [id],
            openReportCount: 0
        )
    }

    /// Six submissions with strictly increasing createdAt (t0 oldest … t5 newest).
    private func sampleSet() -> [Submission] {
        let base = Date(timeIntervalSince1970: 1_767_225_600)
        func at(_ i: Int) -> Date { base.addingTimeInterval(Double(i) * 60) }
        return [
            makeSubmission(id: "s0", type: .proverb, language: .somali, createdAt: at(0), voteScore: 5),
            makeSubmission(id: "s1", type: .poetry, language: .somali, createdAt: at(1), voteScore: 9),
            makeSubmission(id: "s2", type: .proverb, language: .english, createdAt: at(2), voteScore: 1),
            makeSubmission(id: "s3", type: .poetry, language: .english, createdAt: at(3), voteScore: 7),
            makeSubmission(id: "s4", authorUid: "carol", type: .proverb, language: .somali, createdAt: at(4), voteScore: 3),
            makeSubmission(id: "s5", authorUid: "carol", type: .proverb, language: .somali, status: .hidden, createdAt: at(5), voteScore: 8),
        ]
    }

    // MARK: - single fetch

    @Test func fetchByIdReturnsSubmissionAndNilForMissing() async throws {
        let repo = InMemorySubmissionRepository(sampleSet())
        let found = try await repo.submission(id: "s3")
        #expect(found?.id == "s3")
        #expect(found?.type == .poetry)
        let missing = try await repo.submission(id: "does-not-exist")
        #expect(missing == nil)
    }

    // MARK: - feed: only published

    @Test func matchingFeedExcludesHidden() async throws {
        let repo = InMemorySubmissionRepository(sampleSet())
        let page = try await repo.submissions(matching: SubmissionFilter(), after: nil, limit: 50)
        #expect(page.items.count == 5) // s5 is hidden
        #expect(!page.items.contains { $0.id == "s5" })
        #expect(page.items.allSatisfy { $0.status == .published })
    }

    // MARK: - filters

    @Test func filtersByType() async throws {
        let repo = InMemorySubmissionRepository(sampleSet())
        let page = try await repo.submissions(
            matching: SubmissionFilter(type: .poetry), after: nil, limit: 50
        )
        #expect(page.items.compactMap(\.id).sorted() == ["s1", "s3"])
    }

    @Test func filtersByLanguage() async throws {
        let repo = InMemorySubmissionRepository(sampleSet())
        let page = try await repo.submissions(
            matching: SubmissionFilter(language: .english), after: nil, limit: 50
        )
        #expect(page.items.compactMap(\.id).sorted() == ["s2", "s3"])
    }

    @Test func filtersByTypeAndLanguageTogether() async throws {
        let repo = InMemorySubmissionRepository(sampleSet())
        let page = try await repo.submissions(
            matching: SubmissionFilter(type: .proverb, language: .somali), after: nil, limit: 50
        )
        // s0 (published) and s4 (published); s5 is hidden and excluded.
        #expect(page.items.compactMap(\.id).sorted() == ["s0", "s4"])
    }

    // MARK: - sorting

    @Test func sortsByNewestFirst() async throws {
        let repo = InMemorySubmissionRepository(sampleSet())
        let page = try await repo.submissions(
            matching: SubmissionFilter(sort: .newest), after: nil, limit: 50
        )
        // published only, createdAt DESC: s4(t4), s3(t3), s2(t2), s1(t1), s0(t0)
        #expect(page.items.compactMap(\.id) == ["s4", "s3", "s2", "s1", "s0"])
    }

    @Test func sortsByTopRated() async throws {
        let repo = InMemorySubmissionRepository(sampleSet())
        let page = try await repo.submissions(
            matching: SubmissionFilter(sort: .topRated), after: nil, limit: 50
        )
        // published only, voteScore DESC: s1(9), s3(7), s0(5), s4(3), s2(1)
        #expect(page.items.compactMap(\.id) == ["s1", "s3", "s0", "s4", "s2"])
    }

    // MARK: - pagination

    @Test func paginatesWithoutGapsOrDuplicates() async throws {
        let repo = InMemorySubmissionRepository(sampleSet())
        var collected: [String] = []
        var cursor: PageCursor? = nil
        var fetches = 0

        repeat {
            let page = try await repo.submissions(
                matching: SubmissionFilter(sort: .newest), after: cursor, limit: 2
            )
            collected.append(contentsOf: page.items.map { $0.id ?? "" })
            cursor = page.cursor
            fetches += 1
            if page.items.isEmpty { break }
        } while cursor != nil && fetches < 10

        // 5 published items walked in order, no dupes.
        #expect(collected == ["s4", "s3", "s2", "s1", "s0"])
        #expect(Set(collected).count == collected.count)
    }

    @Test func exactlyFullFinalPageYieldsCursorThenEmptyPage() async throws {
        // 4 published items of a single type at limit 2 → two full pages, then a cursor
        // whose follow-up fetch is empty (mirrors Firestore's exactly-full-page behavior).
        let base = Date(timeIntervalSince1970: 1_767_225_600)
        let repo = InMemorySubmissionRepository([
            makeSubmission(id: "a", type: .proverb, createdAt: base.addingTimeInterval(0)),
            makeSubmission(id: "b", type: .proverb, createdAt: base.addingTimeInterval(60)),
            makeSubmission(id: "c", type: .proverb, createdAt: base.addingTimeInterval(120)),
            makeSubmission(id: "d", type: .proverb, createdAt: base.addingTimeInterval(180)),
        ])

        let p1 = try await repo.submissions(matching: SubmissionFilter(type: .proverb), after: nil, limit: 2)
        #expect(p1.items.count == 2)
        #expect(p1.hasMore)

        let p2 = try await repo.submissions(matching: SubmissionFilter(type: .proverb), after: p1.cursor, limit: 2)
        #expect(p2.items.count == 2)
        #expect(p2.hasMore) // full page → cursor present even though nothing remains

        let p3 = try await repo.submissions(matching: SubmissionFilter(type: .proverb), after: p2.cursor, limit: 2)
        #expect(p3.items.isEmpty)
        #expect(!p3.hasMore)
    }

    // MARK: - by author

    @Test func byAuthorExcludesHiddenUnlessRequested() async throws {
        let repo = InMemorySubmissionRepository(sampleSet())

        let publicView = try await repo.submissions(
            byAuthor: "carol", includeHidden: false, after: nil, limit: 50
        )
        #expect(publicView.items.compactMap(\.id) == ["s4"]) // s5 hidden, excluded

        let ownDesk = try await repo.submissions(
            byAuthor: "carol", includeHidden: true, after: nil, limit: 50
        )
        // includes hidden, newest first: s5(t5), s4(t4)
        #expect(ownDesk.items.compactMap(\.id) == ["s5", "s4"])
    }

    // MARK: - count aggregation (13 §A1)

    @Test func publishedCountMatchesPublishedByAuthor() async throws {
        let repo = InMemorySubmissionRepository(sampleSet())
        #expect(try await repo.publishedCount(authorUid: "bob") == 4)   // s0..s3
        #expect(try await repo.publishedCount(authorUid: "carol") == 1) // s4 only; s5 hidden
        #expect(try await repo.publishedCount(authorUid: "nobody") == 0)
    }

    // MARK: - profile repository

    @Test func profileFetchReturnsProfileAndNilForMissing() async throws {
        let profile = Profile(
            id: "seed-official-abwaan",
            displayName: "Abwaan Archive",
            username: "abwaan",
            bio: "",
            photoURL: nil,
            createdAt: Date(timeIntervalSince1970: 1_767_225_600)
        )
        let repo = InMemoryProfileRepository([profile])

        let found = try await repo.profile(uid: "seed-official-abwaan")
        #expect(found?.username == "abwaan")
        #expect(found?.displayName == "Abwaan Archive")

        let missing = try await repo.profile(uid: "deleted")
        #expect(missing == nil)
    }
}
