import XCTest
@testable import YouTubePiPCore

final class RecentSearchesTests: XCTestCase {
    func testAddDedupesIgnoringCaseAccentsAndSpaces() {
        var recent = RecentSearches()
        recent.add("Legião Urbana")
        recent.add("lofi")
        recent.add("  legiao   URBANA ")

        XCTAssertEqual(recent.queries, ["legiao   URBANA", "lofi"])
        recent.add("   ")
        XCTAssertEqual(recent.queries.count, 2)
    }

    func testLimit() {
        var recent = RecentSearches()
        for index in 0..<(RecentSearches.limit + 5) {
            recent.add("busca \(index)")
        }
        XCTAssertEqual(recent.queries.count, RecentSearches.limit)
        XCTAssertEqual(recent.queries.first, "busca \(RecentSearches.limit + 4)")
    }

    func testMatchingAndRemove() {
        var recent = RecentSearches()
        ["Legião Urbana", "Lenine", "Djavan"].forEach { recent.add($0) }

        XCTAssertEqual(recent.matching("le"), ["Lenine", "Legião Urbana"])
        XCTAssertEqual(recent.matching("LEGIAO"), ["Legião Urbana"])
        XCTAssertEqual(recent.matching(""), ["Djavan", "Lenine", "Legião Urbana"])

        recent.remove("lenine")
        XCTAssertEqual(recent.queries, ["Djavan", "Legião Urbana"])
        recent.clear()
        XCTAssertTrue(recent.queries.isEmpty)
    }
}
