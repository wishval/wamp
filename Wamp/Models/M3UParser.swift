import Foundation

struct M3UEntry: Equatable {
    let url: URL
    let duration: TimeInterval?
    let title: String?
}

enum M3UParseError: Error {
    case encoding
}

enum M3UParser {
    static func parse(url: URL) throws -> [M3UEntry] {
        let data = try Data(contentsOf: url)
        let base = url.deletingLastPathComponent()
        let ext = url.pathExtension.lowercased()
        return try parse(data: data, baseURL: base, fileExtension: ext)
    }

    static func parse(
        data: Data,
        baseURL: URL,
        fileExtension: String = "m3u8"
    ) throws -> [M3UEntry] {
        let text = try decode(data, fileExtension: fileExtension)
        return parseText(text, baseURL: baseURL)
    }

    // MARK: - Decoding

    private static func decode(_ data: Data, fileExtension: String) throws -> String {
        var body = data
        if body.starts(with: [0xEF, 0xBB, 0xBF]) {
            body = body.dropFirst(3)
        }
        let preferred: String.Encoding = (fileExtension == "m3u") ? .isoLatin1 : .utf8
        if let s = String(data: body, encoding: preferred) {
            return s
        }
        // Fallback: try the other common encoding.
        let fallback: String.Encoding = (preferred == .utf8) ? .isoLatin1 : .utf8
        if let s = String(data: body, encoding: fallback) {
            return s
        }
        if let s = String(data: body, encoding: .windowsCP1252) {
            return s
        }
        throw M3UParseError.encoding
    }

    // MARK: - Text parsing

    private static func parseText(_ text: String, baseURL: URL) -> [M3UEntry] {
        var entries: [M3UEntry] = []
        var pendingDuration: TimeInterval?
        var pendingTitle: String?

        for rawLine in splitLines(text) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                if line.hasPrefix("#EXTINF:") {
                    (pendingDuration, pendingTitle) = parseExtInf(line)
                }
                // All other directives (including #EXTM3U, unknown ones, bare comments) ignored.
                continue
            }

            // Non-# line → path.
            let resolved = resolveURL(line, baseURL: baseURL)
            entries.append(M3UEntry(
                url: resolved,
                duration: pendingDuration,
                title: pendingTitle
            ))
            pendingDuration = nil
            pendingTitle = nil
        }
        return entries
    }

    private static func parseExtInf(_ line: String) -> (TimeInterval?, String?) {
        // Format: #EXTINF:<duration>[,<title>]
        let afterPrefix = line.dropFirst("#EXTINF:".count)
        let parts = afterPrefix.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let durationStr = parts[0].trimmingCharacters(in: .whitespaces)
        let duration: TimeInterval?
        if let d = Double(durationStr), d >= 0 {
            duration = d
        } else {
            duration = nil
        }
        let title: String?
        if parts.count == 2 {
            let t = String(parts[1]).trimmingCharacters(in: .whitespaces)
            title = t.isEmpty ? nil : t
        } else {
            title = nil
        }
        return (duration, title)
    }

    private static func resolveURL(_ path: String, baseURL: URL) -> URL {
        if path.hasPrefix("file://"), let u = URL(string: path) {
            return u
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
    }

    /// Split on any of CRLF, LF, CR — handling mixed line endings in a single pass.
    /// Iterates over Unicode scalars because Swift treats "\r\n" as a single
    /// grapheme cluster at the Character level, which would skip CRLF splits.
    private static func splitLines(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == "\r" {
                out.append(current)
                current = ""
                i += 1
                if i < scalars.count, scalars[i] == "\n" { i += 1 }
                continue
            }
            if c == "\n" {
                out.append(current)
                current = ""
                i += 1
                continue
            }
            current.unicodeScalars.append(c)
            i += 1
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
