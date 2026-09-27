import Foundation

enum LegacyID3Metadata {
    private nonisolated static let keys = [
        "TT2": "TIT2", "TP1": "TPE1", "TAL": "TALB", "TCO": "TCON",
        "TIT2": "TIT2", "TPE1": "TPE1", "TALB": "TALB", "TCON": "TCON"
    ]
    private nonisolated static let maximumTagSize = 16 * 1024 * 1024

    nonisolated static func read(from url: URL) -> [String: String] {
        guard let file = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? file.close() }
        var fields: [String: Data] = [:]
        var presentKeys = Set<String>()

        if let header = try? file.read(upToCount: 10), header.count == 10 {
            let bytes = Array(header)
            if bytes.starts(with: "ID3".utf8),
               (2...4).contains(bytes[3]),
               let size = integer(bytes[6..<10], syncsafe: true), size <= maximumTagSize,
               let body = try? file.read(upToCount: size), body.count == size {
                readFrames(Array(body), version: Int(bytes[3]), flags: bytes[5],
                           fields: &fields, presentKeys: &presentKeys)
            }
        }

        if let end = try? file.seekToEnd(), end >= 128,
           (try? file.seek(toOffset: end - 128)) != nil,
           let tag = try? file.read(upToCount: 128), tag.count == 128,
           tag.prefix(3) == Data("TAG".utf8) {
            for (key, start) in [("TIT2", 3), ("TPE1", 33), ("TALB", 63)] where !presentKeys.contains(key) {
                fields[key] = tag.subdata(in: start..<(start + 30))
            }
        }
        return decode(fields)
    }

    private nonisolated static func readFrames(
        _ body: [UInt8], version: Int, flags: UInt8,
        fields: inout [String: Data], presentKeys: inout Set<String>
    ) {
        if version == 2 && flags & 0x40 != 0 { return }
        let bytes = version < 4 && flags & 0x80 != 0 ? deunsynchronise(body) : body
        var offset = 0
        if version >= 3 && flags & 0x40 != 0 {
            guard bytes.count >= 4,
                  let size = integer(bytes[0..<4], syncsafe: version == 4) else { return }
            let extendedSize = version == 3 ? size + 4 : size
            guard extendedSize >= (version == 3 ? 10 : 6), extendedSize <= bytes.count else { return }
            offset = extendedSize
        }

        let headerSize = version == 2 ? 6 : 10
        let keySize = version == 2 ? 3 : 4
        while offset + headerSize <= bytes.count {
            let keyBytes = bytes[offset..<(offset + keySize)]
            guard keyBytes.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }),
                  let frameID = String(bytes: keyBytes, encoding: .ascii),
                  let size = integer(bytes[(offset + keySize)..<(offset + headerSize - (version == 2 ? 0 : 2))],
                                     syncsafe: version == 4),
                  size > 0, size <= bytes.count - offset - headerSize else { return }
            let formatFlags = version == 2 ? 0 : bytes[offset + 9]
            var payload = Array(bytes[(offset + headerSize)..<(offset + headerSize + size)])
            offset += headerSize + size
            guard let key = keys[frameID], presentKeys.insert(key).inserted else { continue }

            let unsupported: UInt8 = version == 3 ? 0xC0 : 0x0C
            guard formatFlags & unsupported == 0 else { continue }
            if version == 4 && (flags & 0x80 != 0 || formatFlags & 0x02 != 0) {
                payload = deunsynchronise(payload)
            }
            var prefix = 0
            if formatFlags & (version == 3 ? 0x20 : 0x40) != 0 { prefix += 1 }
            if version == 4 && formatFlags & 0x01 != 0 { prefix += 4 }
            guard payload.count > prefix, payload[prefix] == 0 else { continue }
            if fields[key] == nil { fields[key] = Data(payload.dropFirst(prefix + 1)) }
        }
    }

    nonisolated static func decode(_ fields: [String: Data]) -> [String: String] {
        var textBytes: [String: Data] = [:]
        for (key, data) in fields {
            let bytes = Data(data.prefix { $0 != 0 })
            if !bytes.isEmpty { textBytes[key] = bytes }
        }
        guard !textBytes.isEmpty else { return [:] }

        var sample = Data()
        for key in textBytes.keys.sorted() {
            sample.append(textBytes[key]!)
            sample.append(10)
        }
        let encoding = NSString.stringEncoding(
            for: sample,
            encodingOptions: [
                .suggestedEncodingsKey: [
                    NSNumber(value: String.Encoding.windowsCP1251.rawValue),
                    NSNumber(value: String.Encoding.windowsCP1252.rawValue)
                ],
                .useOnlySuggestedEncodingsKey: true,
                .allowLossyKey: false
            ],
            convertedString: nil, usedLossyConversion: nil
        )
        guard encoding == String.Encoding.windowsCP1251.rawValue else { return [:] }
        return textBytes.compactMapValues {
            guard $0.contains(where: { $0 >= 128 }) else { return nil }
            guard let text = String(data: $0, encoding: .windowsCP1251) else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private nonisolated static func integer(_ bytes: ArraySlice<UInt8>, syncsafe: Bool) -> Int? {
        if syncsafe && bytes.contains(where: { $0 >= 128 }) { return nil }
        return bytes.reduce(0) { ($0 << (syncsafe ? 7 : 8)) | Int($1) }
    }

    private nonisolated static func deunsynchronise(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            result.append(byte)
            index += 1
            if byte == 0xFF && index < bytes.count && bytes[index] == 0 { index += 1 }
        }
        return result
    }
}
