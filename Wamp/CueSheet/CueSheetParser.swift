import Foundation

public enum CueSheetParser {
    public static func parse(url: URL) throws -> CueSheet {
        let data = try Data(contentsOf: url)
        return try parse(data)
    }

    public static func parse(_ data: Data) throws -> CueSheet {
        let decoded = try CueDecoder.decode(data)
        return try parseText(decoded.text)
    }

    static func parseText(_ text: String) throws -> CueSheet {
        var title: String?
        var performer: String?
        var genre: String?
        var date: String?
        let files: [CueFile] = []

        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
        for (idx, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let _ = idx + 1  // line numbers used by later tasks
            let (keyword, rest) = splitKeyword(line)
            switch keyword.uppercased() {
            case "TITLE":
                title = unquote(rest)
            case "PERFORMER":
                performer = unquote(rest)
            case "REM":
                let (subKey, subRest) = splitKeyword(rest)
                switch subKey.uppercased() {
                case "GENRE": genre = unquote(subRest)
                case "DATE":  date  = unquote(subRest)
                default: break
                }
            case "FILE", "TRACK", "INDEX":
                // Handled in later tasks.
                break
            default:
                break
            }
        }

        guard !files.isEmpty, files.contains(where: { !$0.tracks.isEmpty }) else {
            throw CueParseError.noTracks
        }
        return CueSheet(title: title, performer: performer, genre: genre, date: date, files: files)
    }

    /// Split off the first whitespace-delimited token. Returns ("", "") for empty input.
    static func splitKeyword(_ s: String) -> (String, String) {
        guard let space = s.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return (s, "")
        }
        let head = String(s[..<space])
        let tail = String(s[s.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        return (head, tail)
    }

    /// Strip surrounding double quotes if present.
    static func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, t.first == "\"", t.last == "\"" {
            return String(t.dropFirst().dropLast())
        }
        return t
    }
}
