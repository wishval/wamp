import Foundation

public enum CueDecoder {
    public struct Result {
        public let text: String
        public let encoding: String.Encoding
    }

    public static func decode(_ data: Data) throws -> Result {
        // BOM detection
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            let body = data.dropFirst(3)
            guard let s = String(data: body, encoding: .utf8) else { throw CueParseError.encoding }
            return Result(text: s, encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            let body = data.dropFirst(2)
            guard let s = String(data: body, encoding: .utf16LittleEndian) else { throw CueParseError.encoding }
            return Result(text: s, encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            let body = data.dropFirst(2)
            guard let s = String(data: body, encoding: .utf16BigEndian) else { throw CueParseError.encoding }
            return Result(text: s, encoding: .utf16BigEndian)
        }

        // UTF-8 strict (Foundation's String(data:encoding:.utf8) rejects ill-formed sequences).
        if let s = String(data: data, encoding: .utf8), s.utf8.count == data.count {
            return Result(text: s, encoding: .utf8)
        }

        // Candidate chain — implemented in next task
        throw CueParseError.encoding
    }
}
