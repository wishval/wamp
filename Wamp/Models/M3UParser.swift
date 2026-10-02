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
        return fileExtension.lowercased() == "pls"
            ? parsePLS(text, baseURL: baseURL)
            : parseText(text, baseURL: baseURL)
    }

    // MARK: - Decoding

    private static func decode(_ data: Data, fileExtension: String) throws -> String {
        var body = data
        if body.starts(with: [0xEF, 0xBB, 0xBF]) {
            body = body.dropFirst(3)
        }
        // Strict UTF-8 first regardless of extension: it rejects ill-formed
        // sequences, so legacy 8-bit files fall through, while modern tools'
        // UTF-8 .m3u files decode correctly. CP-1252 next (superset of
        // Latin-1's printable range, maps 0x80–0x9F to real glyphs), then
        // Latin-1 as the never-failing last resort.
        if let s = String(data: body, encoding: .utf8) {
            return s
        }
        if let s = String(data: body, encoding: .windowsCP1252) {
            return s
        }
        if let s = String(data: body, encoding: .isoLatin1) {
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
            if let resolved = resolveURL(line, baseURL: baseURL) {
                entries.append(M3UEntry(
                    url: resolved,
                    duration: pendingDuration,
                    title: pendingTitle
                ))
            }
            pendingDuration = nil
            pendingTitle = nil
        }
        return entries
    }

    /// PLS is INI-style: `FileN=`, `TitleN=`, `LengthN=` keyed by entry
    /// number (any order, case-insensitive). Entries come out sorted by N;
    /// `Length` of -1 (unknown / stream) maps to nil.
    private static func parsePLS(_ text: String, baseURL: URL) -> [M3UEntry] {
        var files: [Int: String] = [:]
        var titles: [Int: String] = [:]
        var lengths: [Int: TimeInterval] = [:]

        for rawLine in splitLines(text) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            func entryNumber(_ prefix: String) -> Int? {
                key.hasPrefix(prefix) ? Int(key.dropFirst(prefix.count)) : nil
            }
            if let n = entryNumber("file") {
                files[n] = value
            } else if let n = entryNumber("title") {
                titles[n] = value
            } else if let n = entryNumber("length"), let d = Double(value), d >= 0 {
                lengths[n] = d
            }
        }

        return files.keys.sorted().compactMap { n in
            guard let url = resolveURL(files[n]!, baseURL: baseURL) else { return nil }
            return M3UEntry(url: url, duration: lengths[n], title: titles[n])
        }
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

    /// Returns nil for entries that aren't local files (http/https streams etc.).
    private static func resolveURL(_ path: String, baseURL: URL) -> URL? {
        if path.hasPrefix("file://") {
            if let u = URL(string: path), u.isFileURL {
                return u
            }
            // Legacy tools write unencoded file:// URLs (spaces etc.) —
            // strip the scheme and treat the remainder as a plain path.
            let raw = String(path.dropFirst("file://".count))
            let decoded = raw.removingPercentEncoding ?? raw
            return URL(fileURLWithPath: decoded)
        }
        // Any other scheme:// line (http, https, ...) is a stream — not supported.
        if path.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil {
            return nil
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
