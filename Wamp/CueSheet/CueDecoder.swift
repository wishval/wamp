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

        // Candidate chain — ask Foundation to pick among common cue encodings using
        // its heuristic detection (character statistics + multibyte validity).
        let candidates: [NSNumber] = [
            NSNumber(value: String.Encoding.shiftJIS.rawValue),
            NSNumber(value: String.Encoding.windowsCP1251.rawValue),
            NSNumber(value: String.Encoding.windowsCP1252.rawValue),
            NSNumber(value: String.Encoding.isoLatin1.rawValue),
        ]
        var converted: NSString?
        var lossy: ObjCBool = false
        let recognized = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: candidates,
                .useOnlySuggestedEncodingsKey: true,
            ],
            convertedString: &converted,
            usedLossyConversion: &lossy
        )
        if recognized != 0, let s = converted as String? {
            #if DEBUG
            if lossy.boolValue {
                print("⚠️ CueDecoder: lossy conversion using \(String.Encoding(rawValue: recognized))")
            }
            #endif
            return Result(text: s, encoding: String.Encoding(rawValue: recognized))
        }

        // Last-resort lossy CP-1252.
        if let s = String(data: data, encoding: .windowsCP1252) {
            #if DEBUG
            print("⚠️ CueDecoder: last-resort CP-1252 fallback")
            #endif
            return Result(text: s, encoding: .windowsCP1252)
        }
        throw CueParseError.encoding
    }
}
