// Wamp/Skinning/SkinParser.swift
// Orchestrator. See spec §5.

import AppKit

final class SkinParser {

    /// Synchronous parse for app startup (avoids window flicker).
    func parseSync(contentsOf url: URL) throws -> SkinModel {
        let data = try Data(contentsOf: url)
        return try buildModel(from: data)
    }

    /// Async wrapper for runtime loads (keeps the call off the main thread).
    func parse(contentsOf url: URL) async throws -> SkinModel {
        try await Task.detached(priority: .userInitiated) { [self] in
            let data = try Data(contentsOf: url)
            return try buildModel(from: data)
        }.value
    }

    private func buildModel(from data: Data) throws -> SkinModel {
        let entries = try SkinParserUtils.extractZip(data)

        // main.bmp is the only required file
        guard SkinParserUtils.loadImage(named: "main", from: entries) != nil else {
            throw SkinParserError.missingRequiredFile("main.bmp")
        }

        // All sprite sheets (with nums_ex unification)
        let images = SkinParserUtils.loadAllSheets(from: entries)

        // viscolor.txt
        let viscolors: [NSColor]
        if let viscolorData = entries["viscolor.txt"],
           let text = String(data: viscolorData, encoding: .utf8)
              ?? String(data: viscolorData, encoding: .windowsCP1252) {
            viscolors = ViscolorsParser.parse(text)
        } else {
            viscolors = PlaylistStyle.defaultViscolors
        }

        // pledit.txt
        let playlistStyle: PlaylistStyle
        if let pleditData = entries["pledit.txt"],
           let text = String(data: pleditData, encoding: .utf8)
              ?? String(data: pleditData, encoding: .windowsCP1252) {
            playlistStyle = PlaylistStyleParser.parse(text)
        } else {
            playlistStyle = .default
        }

        // region.txt — main window only
        let region: [CGPoint]?
        if let regionData = entries["region.txt"],
           let text = String(data: regionData, encoding: .utf8)
              ?? String(data: regionData, encoding: .windowsCP1252) {
            region = RegionParser.parseMainWindowRegion(text, windowHeight: 116)
        } else {
            region = nil
        }

        // eqmain.bmp graph line colors
        let eqGraphLines: [NSColor]
        let eqPreampLine: NSColor
        if let eqmain = images["eqmain"] {
            let parsed = EqGraphColorsParser.parse(from: eqmain)
            eqGraphLines = parsed.lines
            eqPreampLine = parsed.preamp
        } else {
            eqGraphLines = []
            eqPreampLine = .green
        }

        return SkinModel(
            images: images,
            viscolors: viscolors,
            playlistStyle: playlistStyle,
            mainWindowRegion: region,
            eqGraphLineColors: eqGraphLines,
            eqPreampLineColor: eqPreampLine
        )
    }
}
