import Testing
import FirebaseFirestore
@testable import abwaan_ios

/// Model Codable round-trips (12-ROADMAP.md M1 Done-when: "Swift tests decode every
/// seeded document without loss"). Uses Firestore.Decoder directly on plain
/// dictionaries — the same decode path `document.data(as:)` uses internally — so no
/// live emulator connection is needed here (that's the rules-unit-testing suite's job).
///
/// Submission and Profile/PrivateUser fixtures below are copied verbatim from
/// firebase/seed/sampleData.js and the values actually written by firebase/seed/seed.js
/// (confirmed against the running emulator, 2026-07-11). Comment/Report/Vote/Favorite
/// have no seeded data yet (their features land in M6/M10), so those are synthetic
/// fixtures built to the exact shape firestore.rules requires, round-tripped through
/// encode→decode to prove no data loss.
///
/// @DocumentID requires a DocumentReference in the decoder's userInfo — that's normally
/// supplied by DocumentSnapshot.data(as:) internally. Decoding a bare dictionary without
/// it throws .decodingIsNotSupported rather than leaving `id` nil (discovered running
/// this suite against a real simulator, 2026-07-11 — the SDK does not silently no-op
/// here). decodeFixture(_:from:at:) below supplies a locally-constructed reference
/// (no network I/O — just a path handle) to keep these tests emulator-free while still
/// exercising real @DocumentID population.
struct ModelRoundTripTests {

    /// Matches FirebaseFirestore's own DocumentSnapshot.data(as:) — the same userInfo
    /// key it sets internally, spelled out here since we're not decoding from a live
    /// snapshot.
    private static let documentRefUserInfoKey = CodingUserInfoKey(rawValue: "DocumentRefUserInfoKey")!

    private func decodeFixture<T: Decodable>(_ type: T.Type, from dict: [String: Any], at path: String) throws -> T {
        var decoder = Firestore.Decoder()
        decoder.userInfo[Self.documentRefUserInfoKey] = Firestore.firestore().document(path)
        return try decoder.decode(type, from: dict)
    }

    // MARK: - Submission (seeded)

    @Test func decodesSeedProverbLaAan() throws {
        let dict: [String: Any] = [
            "authorUid": "seed-official-abwaan",
            "authorUsername": "abwaan",
            "type": "Proverb",
            "language": "so",
            "origin": "original",
            "status": "published",
            "title": NSNull(),
            "text": "Aqoon la'aan waa iftiin la'aan.",
            "meaning": "Knowledge is equated to light, and its absence leaves one in darkness. It emphasizes the critical importance of education and awareness in navigating life.",
            "translation": "Lack of knowledge is lack of light.",
            "source": NSNull(),
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_767_225_600)),
            "updatedAt": NSNull(),
            "voteUp": 0,
            "voteDown": 0,
            "voteScore": 0,
            "searchIndex": "aqoon la'aan waa iftiin la'aan",
            "searchKeywords": [
                "proverb", "abwaan", "aqoon", "la'aan", "waa", "iftiin",
                "knowledge", "equated", "light", "and", "its", "absence", "leaves", "one", "in",
                "darkness", "it", "emphasizes", "the", "critical", "importance", "of", "education",
                "awareness", "navigating", "life",
            ],
            "openReportCount": 0,
        ]

        let submission = try decodeFixture(Submission.self, from: dict, at: "submissions/seed-0")

        #expect(submission.id == "seed-0")
        #expect(submission.type == .proverb)
        #expect(submission.language == .somali)
        #expect(submission.origin == .original)
        #expect(submission.status == .published)
        #expect(submission.title == nil)
        #expect(submission.text == "Aqoon la'aan waa iftiin la'aan.")
        #expect(submission.meaning != nil)
        #expect(submission.translation == "Lack of knowledge is lack of light.")
        #expect(submission.source == nil)
        #expect(submission.updatedAt == nil)
        #expect(submission.voteUp == 0 && submission.voteDown == 0 && submission.voteScore == 0)
        #expect(submission.openReportCount == 0)
        // A9: the apostrophe in the decoded searchIndex is the folded ASCII form.
        #expect(submission.searchIndex == "aqoon la'aan waa iftiin la'aan")
        #expect(submission.searchIndex.contains("'"))
        #expect(submission.statusChangedAt == nil)
        #expect(submission.statusChangedBy == nil)
        #expect(submission.statusReason == nil)
    }

    @Test func decodesSeedAttributedGabay() throws {
        // seed-4 — "Dardaaran": multi-line text, origin == .attributed, title required.
        let text = "Nin ragow haween u galgalan, waanadaa garane\nGeedkii ninkii la gubay, waad u jeedaan-e\nSida gorayga ciidda leh, ha noqon, gabayga aad sheegto."
        let dict: [String: Any] = [
            "authorUid": "seed-official-abwaan",
            "authorUsername": "abwaan",
            "type": "Poetry",
            "language": "so",
            "origin": "attributed",
            "status": "published",
            "title": "Dardaaran",
            "text": text,
            "meaning": "This excerpt is attributed to the famous poet Sayid Mohamed Abdulle Hassan, advising men to be mindful of their actions and not to be reckless in their dealings or speech, comparing folly to an ostrich burying its head in the sand.",
            "translation": "Oh man, do not trifle with women, understand the advice,\nYou see what happened to the man whose tree was burned,\nDo not be like the ostrich in the sand, in the poems you recite.",
            "source": NSNull(),
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_767_225_840)),
            "updatedAt": NSNull(),
            "voteUp": 0, "voteDown": 0, "voteScore": 0,
            "searchIndex": "dardaaran",
            "searchKeywords": ["poetry", "abwaan", "dardaaran"],
            "openReportCount": 0,
        ]

        let submission = try decodeFixture(Submission.self, from: dict, at: "submissions/seed-4")

        #expect(submission.id == "seed-4")
        #expect(submission.type == .poetry)
        #expect(submission.origin == .attributed)
        #expect(submission.title == "Dardaaran")
        // Multi-line text survives the round trip with embedded newlines intact.
        #expect(submission.text.contains("\n"))
        #expect(submission.text == text)
        #expect(submission.searchIndex == "dardaaran") // title, not text — fix #1, 10 §7
    }

    @Test(arguments: [
        (id: "seed-1", text: "Far keliya fool ma dhaqdo.", type: SubmissionType.proverb, title: String?.none),
        (id: "seed-2", text: "Nin aan dhididin, dhagax kama helo.", type: SubmissionType.proverb, title: String?.none),
        (id: "seed-3", text: "Rag waa ragii hore, hadalna waa tii hore.", type: SubmissionType.proverb, title: String?.none),
        (id: "seed-5", text: "Ninkii aan lahayn geel jire\nEe aan lahayn gabay tirshe\nMa guuleysto weligiis.", type: SubmissionType.poetry, title: "Ninkii aan lahayn"),
    ])
    func decodesRemainingSeedEntries(fixture: (id: String, text: String, type: SubmissionType, title: String?)) throws {
        var dict: [String: Any] = [
            "authorUid": "seed-official-abwaan",
            "authorUsername": "abwaan",
            "type": fixture.type.rawValue,
            "language": "so",
            "origin": "original",
            "status": "published",
            "title": fixture.title as Any? ?? NSNull(),
            "text": fixture.text,
            "meaning": "placeholder meaning",
            "translation": "placeholder translation",
            "source": NSNull(),
            "createdAt": Timestamp(date: Date()),
            "updatedAt": NSNull(),
            "voteUp": 0, "voteDown": 0, "voteScore": 0,
            "searchIndex": (fixture.title ?? fixture.text).lowercased(),
            "searchKeywords": ["placeholder"],
            "openReportCount": 0,
        ]
        if fixture.title == nil { dict["title"] = NSNull() }

        let submission = try decodeFixture(Submission.self, from: dict, at: "submissions/\(fixture.id)")
        #expect(submission.id == fixture.id)
        #expect(submission.text == fixture.text)
        #expect(submission.type == fixture.type)
        #expect(submission.title == fixture.title)
    }

    // MARK: - Profile / PrivateUser (seeded author)

    @Test func decodesSeedAuthorProfile() throws {
        let dict: [String: Any] = [
            "displayName": "Abwaan Archive",
            "username": "abwaan",
            "bio": "Official seed account for M1 sample content. Not yet native-speaker verified (13 §B2).",
            "photoURL": NSNull(),
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_767_225_600)),
        ]
        let profile = try decodeFixture(Profile.self, from: dict, at: "profiles/seed-official-abwaan")

        #expect(profile.id == "seed-official-abwaan")
        #expect(profile.displayName == "Abwaan Archive")
        #expect(profile.username == "abwaan")
        #expect(profile.photoURL == nil)
    }

    @Test func decodesSeedAuthorPrivateUser() throws {
        let dict: [String: Any] = [
            "email": "",
            "providerId": NSNull(),
            "lastLoginAt": Timestamp(date: Date(timeIntervalSince1970: 1_767_225_600)),
            "blockedUids": [String](),
        ]
        let privateUser = try decodeFixture(PrivateUser.self, from: dict, at: "privateUsers/seed-official-abwaan")

        #expect(privateUser.id == "seed-official-abwaan")
        #expect(privateUser.providerId == nil)
        #expect(privateUser.blockedUids.isEmpty)
    }

    // MARK: - Comment / Report / Vote / Favorite (no seeded data — round-trip only)

    @Test func commentRoundTripsWithoutLoss() throws {
        // Testing.Comment (an #expect annotation type) collides with our model's
        // Comment when both are in unqualified scope — module-qualify ours.
        // @ServerTimestamp left nil encodes to a FieldValue.serverTimestamp() sentinel
        // (correct for a real write — Firestore resolves it on commit) which cannot be
        // decoded back locally, since that sentinel never actually persists. Passing a
        // concrete Date makes this a realistic "read an already-written doc" fixture.
        let original = abwaan_ios.Comment(
            authorUid: "alice",
            authorUsername: "alice",
            body: "Waa run, aad baa mahadsantahay.",
            createdAt: Date(timeIntervalSince1970: 1_767_225_600)
        )
        let encoded = try Firestore.Encoder().encode(original)
        let decoded = try decodeFixture(
            abwaan_ios.Comment.self, from: encoded, at: "submissions/sub1/comments/c1"
        )

        #expect(decoded.id == "c1")
        #expect(decoded.authorUid == original.authorUid)
        #expect(decoded.authorUsername == original.authorUsername)
        #expect(decoded.body == original.body)
    }

    @Test func reportRoundTripsWithoutLoss() throws {
        let original = Report(
            submissionId: "sub1",
            submissionType: .proverb,
            submissionTitle: "",
            submissionAuthorUid: "bob",
            submissionAuthorUsername: "bob",
            reporterUid: "alice",
            reporterUsername: "alice",
            reason: .spam,
            details: nil,
            status: .open,
            createdAt: Date(timeIntervalSince1970: 1_767_225_600),
            reviewedAt: nil,
            reviewedBy: nil
        )
        let encoded = try Firestore.Encoder().encode(original)
        let decoded = try decodeFixture(
            Report.self, from: encoded, at: "submissions/sub1/reports/alice"
        )

        #expect(decoded.id == "alice")
        #expect(decoded.submissionId == original.submissionId)
        #expect(decoded.submissionType == .proverb)
        #expect(decoded.reason == .spam)
        #expect(decoded.status == .open)
        #expect(decoded.details == nil)
        #expect(decoded.reviewedAt == nil)
    }

    @Test func voteRoundTripsWithoutLoss() throws {
        let dict: [String: Any] = [
            "value": 1,
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_767_225_600)),
            "updatedAt": NSNull(),
        ]
        let vote = try decodeFixture(Vote.self, from: dict, at: "submissions/sub1/votes/alice")
        #expect(vote.id == "alice")
        #expect(vote.value == 1)
        #expect(vote.updatedAt == nil)
    }

    @Test func favoriteRoundTripsWithoutLoss() throws {
        // Same @ServerTimestamp sentinel issue as Comment/Report above — a concrete
        // Date models a doc already resolved by the server, which is what a decode
        // path actually reads.
        let original = Favorite(savedAt: Date(timeIntervalSince1970: 1_767_225_600))
        let encoded = try Firestore.Encoder().encode(original)
        let decoded = try decodeFixture(
            Favorite.self, from: encoded, at: "privateUsers/alice/favorites/sub1"
        )
        #expect(decoded.id == "sub1")
        #expect(decoded.savedAt == original.savedAt)
    }

    // MARK: - Enum wire-value fidelity (10 §4 #5: "attributed", not the web's "shared")

    @Test func originEnumUsesAttributedNotShared() {
        #expect(SubmissionOrigin.attributed.rawValue == "attributed")
        #expect(SubmissionOrigin(rawValue: "shared") == nil)
    }

    @Test func languageEnumRestrictsToSoAndEn() {
        #expect(LanguageCode(rawValue: "so") == .somali)
        #expect(LanguageCode(rawValue: "en") == .english)
        #expect(LanguageCode(rawValue: "fr") == nil)
    }
}
