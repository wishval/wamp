import Foundation

/// Debug-only console logging, tagged with the call site. Compiles to nothing
/// in Release so playback diagnostics don't spam the system log.
nonisolated func debugLog(
    _ items: Any...,
    separator: String = " ",
    function: String = #function,
    file: String = #fileID,
    line: Int = #line
) {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    let fileName = (file as NSString).lastPathComponent
    print("[\(fileName):\(line)] \(function) → \(output)")
    #endif
}
