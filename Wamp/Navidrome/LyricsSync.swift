import Foundation

/// Pure helpers for following synced lyrics. Kept UI-free so the
/// line-selection rule is unit-testable.
enum LyricsSync {
    /// Index of the line that should be highlighted at `time` (seconds): the
    /// last line whose start is at or before `time`. Nil before the first
    /// line starts. `startsMs` must be ascending.
    static func currentLineIndex(startsMs: [Int], time: TimeInterval) -> Int? {
        let ms = Int((time * 1000).rounded(.down))
        var lo = 0, hi = startsMs.count - 1, found: Int? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if startsMs[mid] <= ms {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }

    /// Pick the best block from a `getLyricsBySongId` response: prefer a
    /// synced block, then the first non-empty one.
    static func preferred(_ blocks: [SubsonicLyrics]) -> SubsonicLyrics? {
        blocks.first(where: { $0.isSynced }) ?? blocks.first(where: { !$0.lines.isEmpty })
    }
}
