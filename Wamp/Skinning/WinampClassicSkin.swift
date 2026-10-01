// Wamp/Skinning/WinampClassicSkin.swift
// SkinProvider impl backed by a parsed SkinModel. See spec §6.

import AppKit

final class WinampClassicSkin: SkinProvider {
    private let model: SkinModel
    private let cache = NSCache<NSString, NSImage>()
    private var missingKeys = Set<SpriteKey>()

    init(model: SkinModel) {
        self.model = model
    }

    func sprite(_ key: SpriteKey) -> NSImage? {
        let cacheKey = "\(key)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        if missingKeys.contains(key) { return nil }

        let info = SpriteCoordinates.resolve(key)
        guard let sheet = model.images[info.sheet] else {
            missingKeys.insert(key)
            return nil
        }
        let sheetBounds = CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height)
        guard sheetBounds.contains(info.rect) else {
            missingKeys.insert(key)
            return nil
        }
        guard let cropped = sheet.cropping(to: info.rect) else {
            missingKeys.insert(key)
            return nil
        }
        // cropping(to:) intersects with the sheet bounds: a truncated sheet
        // yields a smaller image that would be stretched to the sprite size.
        // Treat partial sprites as missing so views use their fallback drawing.
        guard cropped.width == Int(info.rect.width),
              cropped.height == Int(info.rect.height) else {
            missingKeys.insert(key)
            return nil
        }

        let image = NSImage(cgImage: cropped, size: info.rect.size)
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    var textSheet: NSImage? {
        guard let cg = model.images["text"] else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    var viscolors: [NSColor] { model.viscolors }
    var playlistStyle: PlaylistStyle { model.playlistStyle }
    var eqGraphLineColors: [NSColor] { model.eqGraphLineColors }
    var eqPreampLineColor: NSColor { model.eqPreampLineColor }

    var mainWindowRegion: NSBezierPath? {
        guard let polygons = model.mainWindowRegion else { return nil }
        let path = NSBezierPath()
        for poly in polygons where poly.count >= 3 {
            path.move(to: poly[0])
            for p in poly.dropFirst() { path.line(to: p) }
            path.close()
        }
        return path.isEmpty ? nil : path
    }
}
