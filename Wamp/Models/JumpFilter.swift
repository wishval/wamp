import Foundation

/// Pure substring-with-ranking matcher used by the Jump-to-file dialog.
///
/// Three tiers (lower number = better match):
///   1. Prefix:        query matches at the very start of the haystack
///   2. Word boundary: query matches right after a space or dash
///   3. Substring:     query matches anywhere else
///
/// Within a tier, original `index` order is preserved.
enum JumpFilter {
    struct Candidate {
        let index: Int
        let displayTitle: String  // e.g. "Pink Floyd - Money"
        let filename: String      // e.g. "track01.mp3"
    }

    struct Match {
        let index: Int
        let tier: Int
    }

    /// Returns matches ordered by tier then original index.
    /// Empty/whitespace query returns every candidate in its original order.
    static func filter(query: String, candidates: [Candidate]) -> [Match] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty {
            return candidates.map { Match(index: $0.index, tier: 0) }
        }

        var matches: [Match] = []
        matches.reserveCapacity(candidates.count)

        for c in candidates {
            let t = tier(for: trimmed, in: c.displayTitle.lowercased())
            if t > 0 {
                matches.append(Match(index: c.index, tier: t))
                continue
            }
            let ft = tier(for: trimmed, in: c.filename.lowercased())
            if ft > 0 {
                matches.append(Match(index: c.index, tier: ft))
            }
        }

        // Stable sort: encode the original position into a secondary key so
        // that ties within a tier preserve insertion order.
        let indexed = matches.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { lhs, rhs in
            if lhs.1.tier != rhs.1.tier { return lhs.1.tier < rhs.1.tier }
            return lhs.0 < rhs.0
        }
        return sorted.map { $0.1 }
    }

    /// Returns 1 (prefix), 2 (word boundary), 3 (substring), or 0 (no match).
    /// `query` and `haystack` must already be lowercased.
    private static func tier(for query: String, in haystack: String) -> Int {
        guard !query.isEmpty, !haystack.isEmpty else { return 0 }
        if haystack.hasPrefix(query) { return 1 }
        guard let range = haystack.range(of: query) else { return 0 }
        let prevIdx = haystack.index(before: range.lowerBound)
        let prev = haystack[prevIdx]
        if prev == " " || prev == "-" || prev == "\t" { return 2 }
        return 3
    }
}
