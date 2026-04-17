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

        struct PendingFile {
            var path: String
            var format: String
            var tracks: [CueTrack] = []
        }
        struct PendingTrack {
            var number: Int
            var title: String?
            var performer: String?
            var startFrames: Int?  // from INDEX 01
        }

        var files: [PendingFile] = []
        var currentFile: PendingFile?
        var currentTrack: PendingTrack?
        var lastTrackLine: Int = 0
        var lastFileLine: Int = 0

        func flushTrack(at line: Int) throws {
            guard let t = currentTrack else { return }
            guard let start = t.startFrames else {
                throw CueParseError.malformed(line: line, reason: "TRACK \(t.number) missing INDEX 01")
            }
            currentFile?.tracks.append(CueTrack(
                number: t.number, title: t.title, performer: t.performer, startFrames: start
            ))
            currentTrack = nil
        }

        func flushFile(at line: Int) throws {
            try flushTrack(at: line)
            if let f = currentFile { files.append(f) }
            currentFile = nil
        }

        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
        for (idx, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lineNo = idx + 1
            let (keyword, rest) = splitKeyword(line)
            switch keyword.uppercased() {
            case "TITLE":
                if currentTrack != nil { currentTrack?.title = unquote(rest) }
                else { title = unquote(rest) }
            case "PERFORMER":
                if currentTrack != nil { currentTrack?.performer = unquote(rest) }
                else { performer = unquote(rest) }
            case "REM":
                let (subKey, subRest) = splitKeyword(rest)
                switch subKey.uppercased() {
                case "GENRE": genre = unquote(subRest)
                case "DATE":  date  = unquote(subRest)
                default: break
                }
            case "FILE":
                try flushFile(at: lastFileLine > 0 ? lastFileLine : lineNo)
                let (pathPart, formatPart) = splitFileLine(rest)
                currentFile = PendingFile(path: pathPart, format: formatPart.uppercased())
                lastFileLine = lineNo
                lastTrackLine = 0
            case "TRACK":
                guard currentFile != nil else {
                    throw CueParseError.malformed(line: lineNo, reason: "TRACK before FILE")
                }
                try flushTrack(at: lastTrackLine > 0 ? lastTrackLine : lineNo)
                let (numStr, _) = splitKeyword(rest)
                guard let num = Int(numStr) else {
                    throw CueParseError.malformed(line: lineNo, reason: "invalid TRACK number '\(numStr)'")
                }
                currentTrack = PendingTrack(number: num)
                lastTrackLine = lineNo
            case "INDEX":
                guard currentTrack != nil else {
                    throw CueParseError.malformed(line: lineNo, reason: "INDEX outside TRACK")
                }
                let (idxStr, timeStr) = splitKeyword(rest)
                guard let indexNo = Int(idxStr) else {
                    throw CueParseError.malformed(line: lineNo, reason: "invalid INDEX number '\(idxStr)'")
                }
                if indexNo == 1 {
                    guard let f = parseTimecode(timeStr) else {
                        throw CueParseError.malformed(line: lineNo, reason: "invalid timecode '\(timeStr)'")
                    }
                    currentTrack?.startFrames = f
                }
                // INDEX 00 (pregap) and others are intentionally ignored.
            default:
                break
            }
        }
        try flushFile(at: lastTrackLine > 0 ? lastTrackLine : lastFileLine)

        guard !files.isEmpty, files.contains(where: { !$0.tracks.isEmpty }) else {
            throw CueParseError.noTracks
        }
        let resolvedFiles = files.map { CueFile(path: $0.path, format: $0.format, tracks: $0.tracks) }
        return CueSheet(title: title, performer: performer, genre: genre, date: date, files: resolvedFiles)
    }

    /// FILE "name with spaces.flac" WAVE  →  ("name with spaces.flac", "WAVE")
    /// FILE name.wav WAVE                 →  ("name.wav",              "WAVE")
    static func splitFileLine(_ s: String) -> (String, String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.first == "\"" {
            if let closing = t.dropFirst().firstIndex(of: "\"") {
                let path = String(t[t.index(after: t.startIndex)..<closing])
                let rest = String(t[t.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
                return (path, rest)
            }
            return (String(t.dropFirst()), "")
        }
        return splitKeyword(t)
    }

    /// "MM:SS:FF" → frame count (1/75 sec).
    static func parseTimecode(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 3,
              let m = Int(parts[0]), let sec = Int(parts[1]), let f = Int(parts[2]),
              m >= 0, sec >= 0, sec < 60, f >= 0, f < 75 else { return nil }
        return ((m * 60) + sec) * 75 + f
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
