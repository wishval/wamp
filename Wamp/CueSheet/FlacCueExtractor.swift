import Foundation

enum FlacCueExtractorError: Error {
    case notFlac
    case truncated
}

enum FlacCueExtractor {
    /// Returns the value of the `CUESHEET` Vorbis comment in `url`, or nil if absent.
    /// Throws `.notFlac` if the file does not begin with the FLAC magic; `.truncated`
    /// if a metadata block's declared length extends past the end of the data.
    static func extractCueSheet(from url: URL) throws -> String? {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 4,
              data[0] == 0x66, data[1] == 0x4C, data[2] == 0x61, data[3] == 0x43 else {
            throw FlacCueExtractorError.notFlac
        }
        var cursor = 4
        while cursor + 4 <= data.count {
            let header = data[cursor]
            let isLast = (header & 0x80) != 0
            let type   = Int(header & 0x7F)
            let len = (Int(data[cursor + 1]) << 16) |
                      (Int(data[cursor + 2]) << 8)  |
                       Int(data[cursor + 3])
            cursor += 4
            guard cursor + len <= data.count else { throw FlacCueExtractorError.truncated }
            let block = data.subdata(in: cursor..<(cursor + len))
            cursor += len

            if type == 4 {  // VORBIS_COMMENT
                if let cue = parseVorbisCueSheet(block) { return cue }
            }
            if isLast { break }
        }
        return nil
    }

    private static func parseVorbisCueSheet(_ data: Data) -> String? {
        var p = 0
        guard p + 4 <= data.count else { return nil }
        let vendorLen = Int(readUInt32LE(data, at: p)); p += 4
        guard p + vendorLen <= data.count else { return nil }
        p += vendorLen
        guard p + 4 <= data.count else { return nil }
        let count = Int(readUInt32LE(data, at: p)); p += 4
        for _ in 0..<count {
            guard p + 4 <= data.count else { return nil }
            let len = Int(readUInt32LE(data, at: p)); p += 4
            guard p + len <= data.count else { return nil }
            let raw = data.subdata(in: p..<(p + len))
            p += len
            guard let s = String(data: raw, encoding: .utf8) else { continue }
            if let eq = s.firstIndex(of: "=") {
                let key = s[..<eq].uppercased()
                if key == "CUESHEET" {
                    return String(s[s.index(after: eq)...])
                }
            }
        }
        return nil
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[data.startIndex + offset]) |
        (UInt32(data[data.startIndex + offset + 1]) << 8) |
        (UInt32(data[data.startIndex + offset + 2]) << 16) |
        (UInt32(data[data.startIndex + offset + 3]) << 24)
    }
}
