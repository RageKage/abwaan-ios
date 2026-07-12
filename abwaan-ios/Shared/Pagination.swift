import Foundation

/// A page of results plus an opaque cursor to resume after.
///
/// `PageCursor` hides whatever a repository needs to continue a query — a Firestore
/// `DocumentSnapshot` in the live implementation, an index in the in-memory fake — so
/// **no Firebase type crosses the repository boundary** (CLAUDE.md / 10 §2, the answer
/// to Swift 6 concurrency, R3). The model/store layer holds and passes back only this
/// `Sendable` token; it never inspects the contents.
///
/// This deliberately supersedes the `cursor: DocumentSnapshot?` sketch in 10 §5, which
/// would have leaked a non-`Sendable` Firebase type into the view-model layer.
struct Page<Item: Sendable>: Sendable {
    let items: [Item]
    let cursor: PageCursor?

    /// True when another page may exist. Mirrors Firestore's own semantics: a cursor is
    /// produced whenever a full page was returned, so `hasMore` can be true even when the
    /// next fetch turns out empty (an exactly-full final page). Callers should stop when a
    /// fetch returns no items, not solely on `hasMore`.
    var hasMore: Bool { cursor != nil }

    init(items: [Item], cursor: PageCursor?) {
        self.items = items
        self.cursor = cursor
    }
}

/// Opaque pagination token. Only the repository that produced a cursor can interpret it;
/// do not construct or unwrap one outside a `…Repository` implementation, and never mix a
/// cursor from one repository into another (their payloads differ).
struct PageCursor: @unchecked Sendable {
    // `@unchecked Sendable` is justified: the boxed value is either a Firestore
    // `DocumentSnapshot` (effectively immutable) or an `Int` index. It is never mutated,
    // and is only ever unwrapped by the same repository implementation that created it, so
    // transferring it across actors is safe even though `DocumentSnapshot` is not `Sendable`.
    let boxed: Any

    init(_ boxed: Any) {
        self.boxed = boxed
    }
}
