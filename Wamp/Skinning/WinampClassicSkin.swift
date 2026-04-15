// Wamp/Skinning/WinampClassicSkin.swift
// SkinProvider impl backed by a parsed SkinModel. See spec §6.

import AppKit

final class WinampClassicSkin: SkinProvider {
    private let model: SkinModel
    private let cache = NSCache<NSString, NSImage>()

    init(model: SkinModel) {
        self.model = model
    }

    func sprite(_ key: SpriteKey) -> NSImage? {
        let cacheKey = "\(key)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        let info = SpriteCoordinates.resolve(key)
        guard let sheet = model.images[info.sheet] else { return nil }
        guard let cropped = sheet.cropping(to: info.rect) else { return nil }

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
