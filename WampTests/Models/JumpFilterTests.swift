import Testing
import Foundation
@testable import Wamp

@Suite("JumpFilter")
struct JumpFilterTests {

    private func candidates(_ items: [(String, String)]) -> [JumpFilter.Candidate] {
        items.enumerated().map { idx, pair in
            JumpFilter.Candidate(index: idx, displayTitle: pair.0, filename: pair.1)
        }
    }

    @Test func emptyQuery_returnsAllInOriginalOrder() {
        let cs = candidates([("Pink Floyd - Money", "money.mp3"),
                             ("Queen - Bohemian Rhapsody", "queen.mp3")])
        let result = JumpFilter.filter(query: "", candidates: cs)
        #expect(result.map(\.index) == [0, 1])
    }

    @Test func whitespaceOnlyQuery_returnsAll() {
        let cs = candidates([("a", "a.mp3"), ("b", "b.mp3")])
        let result = JumpFilter.filter(query: "   ", candidates: cs)
        #expect(result.map(\.index) == [0, 1])
    }

    @Test func substring_caseInsensitive_matchesArtistOrTitle() {
        let cs = candidates([("Pink Floyd - Money", "01.mp3"),
                             ("Queen - Bohemian Rhapsody", "02.mp3"),
                             ("Daft Punk - Around the World", "03.mp3")])
        let result = JumpFilter.filter(query: "pink", candidates: cs)
        #expect(result.map(\.index) == [0])
    }

    @Test func substring_fallsBackToFilenameWhenDisplayTitleDoesNotMatch() {
        let cs = candidates([("Untitled - Untitled", "rare-keyword.mp3")])
        let result = JumpFilter.filter(query: "rare", candidates: cs)
        #expect(result.map(\.index) == [0])
    }

    @Test func ranking_prefixBeatsWordBoundaryBeatsSubstring() {
        // "abc" appears in three different positions:
        //   index 0: substring deep inside ("xyzabcxyz")        -> tier 3
        //   index 1: word-boundary in middle ("foo abcdef")     -> tier 2
        //   index 2: prefix at very start ("abcdef ghi")        -> tier 1
        let cs = candidates([("xyzabcxyz", "0.mp3"),
                             ("foo abcdef", "1.mp3"),
                             ("abcdef ghi", "2.mp3")])
        let result = JumpFilter.filter(query: "abc", candidates: cs)
        #expect(result.map(\.index) == [2, 1, 0])
    }

    @Test func ranking_withinSameTier_preservesOriginalOrder() {
        // All three are pure substring matches at identical positions.
        let cs = candidates([("xxabcxx", "0.mp3"),
                             ("yyabcyy", "1.mp3"),
                             ("zzabczz", "2.mp3")])
        let result = JumpFilter.filter(query: "abc", candidates: cs)
        #expect(result.map(\.index) == [0, 1, 2])
    }

    @Test func wordBoundary_matchesAfterDashOrSpace() {
        // "alpha - rider" -> 'r' at index 8 is a word boundary (preceded by space).
        // "alpharider"    -> 'r' at index 5 is a substring (no boundary).
        let cs = candidates([("alpha - rider", "0.mp3"),
                             ("alpharider", "1.mp3")])
        let result = JumpFilter.filter(query: "rider", candidates: cs)
        #expect(result.map(\.index) == [0, 1])
    }

    @Test func noMatches_returnsEmpty() {
        let cs = candidates([("a", "a.mp3"), ("b", "b.mp3")])
        let result = JumpFilter.filter(query: "zzzz", candidates: cs)
        #expect(result.isEmpty)
    }

    @Test func performance_under16msFor10kTracks() {
        // Generate 10k synthetic tracks. Half of them contain "abc" somewhere.
        let cs: [JumpFilter.Candidate] = (0..<10_000).map { i in
            let display = i % 2 == 0
                ? "Artist\(i) - Track abc \(i)"
                : "Other\(i) - Random \(i)"
            return JumpFilter.Candidate(index: i, displayTitle: display, filename: "\(i).mp3")
        }
        let start = Date()
        _ = JumpFilter.filter(query: "abc", candidates: cs)
        let elapsedMs = Date().timeIntervalSince(start) * 1000
        #expect(elapsedMs < 16, "JumpFilter took \(elapsedMs)ms on 10k tracks (target <16ms)")
    }
}
