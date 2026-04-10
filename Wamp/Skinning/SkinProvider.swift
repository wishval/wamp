// Wamp/Skinning/SkinProvider.swift
// Provider protocol + BuiltInSkin (no skin loaded). See spec §6.

import AppKit

protocol SkinProvider: AnyObject {
    /// Returns the requested sprite as an NSImage, or nil if the underlying sheet is missing.
    func sprite(_ key: SpriteKey) -> NSImage?

    /// The full text.bmp sheet, for TextSpriteRenderer to slice glyphs from.
    var textSheet: NSImage? { get }

    var viscolors: [NSColor] { get }
    var playlistStyle: PlaylistStyle { get }
    var eqGraphLineColors: [NSColor] { get }
    var eqPreampLineColor: NSColor { get }
    var mainWindowRegion: NSBezierPath? { get }
}

/// The "no skin loaded" provider. All sprite() calls return nil and views fall through
/// to their built-in (programmatic) rendering paths. This is the default state.
final class BuiltInSkin: SkinProvider {
    func sprite(_ key: SpriteKey) -> NSImage? { nil }
    var textSheet: NSImage? { nil }
    var viscolors: [NSColor] { PlaylistStyle.defaultViscolors }
    var playlistStyle: PlaylistStyle { .default }
    var eqGraphLineColors: [NSColor] { [] }
    var eqPreampLineColor: NSColor { .green }
    var mainWindowRegion: NSBezierPath? { nil }
}
