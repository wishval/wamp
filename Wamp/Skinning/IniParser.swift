// Wamp/Skinning/IniParser.swift
// Generic INI parser used by playlist style and region. See spec §3.

import Foundation

enum IniParser {
    /// Parses INI text into [section: [key: value]]. All keys lowercased.
    /// Handles BOM, CRLF, ; comments, and quoted values.
    static func parse(_ text: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var section: String?

        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")

        let sectionRegex = try! NSRegularExpression(pattern: #"^\s*\[(.+?)\]\s*$"#)
        let propertyRegex = try! NSRegularExpression(pattern: #"^\s*([^;][^=]*?)\s*=\s*(.*?)\s*$"#)

        for line in cleaned.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix(";") { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)

            if let m = sectionRegex.firstMatch(in: trimmed, range: range),
               let r = Range(m.range(at: 1), in: trimmed) {
                section = String(trimmed[r]).lowercased()
                if result[section!] == nil { result[section!] = [:] }
            } else if let s = section,
                      let m = propertyRegex.firstMatch(in: trimmed, range: range),
                      let kr = Range(m.range(at: 1), in: trimmed),
                      let vr = Range(m.range(at: 2), in: trimmed) {
                let key = String(trimmed[kr]).lowercased()
                var value = String(trimmed[vr])
                if value.count >= 2,
                   (value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'") {
                    value = String(value.dropFirst().dropLast())
                }
                result[s]?[key] = value
            }
        }
        return result
    }
}
