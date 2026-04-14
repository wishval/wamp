import Cocoa
import Combine
import UniformTypeIdentifiers

class PlaylistView: NSView {
    private static let internalRowType = NSPasteboard.PasteboardType("com.winampmac.playlist.row")

    private let titleBar = TitleBarView()
    private let scrollView = NSScrollView()
    private let tableView = PlaylistTableView()
    private let searchField = NSTextField()
    private let addButton = WinampButton(title: "ADD", style: .action)
    private let remButton = WinampButton(title: "REM", style: .action)
    private let remAllButton = WinampButton(title: "CLEAR", style: .action)
    private let listOptsButton = WinampButton(title: "LISTS", style: .action)
    private let infoLabel = NSTextField(labelWithString: "")
    private let skinScroller = PlaylistSkinScroller()

    private var cancellables = Set<AnyCancellable>()
    private var skinObserver: AnyCancellable?
    private weak var playlistManager: PlaylistManager?
    private var lastColumnWidth: CGFloat = 0
    private var dragOrigin: NSPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
        setupSubviews()
        registerForDraggedTypes([.fileURL])
        tableView.registerForDraggedTypes([PlaylistView.internalRowType, .fileURL])
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSubviews() {
        titleBar.titleText = "WAMP PLAYLIST"
        titleBar.showButtons = false
        addSubview(titleBar)

        // Table view
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        column.width = WinampTheme.windowWidth - 20
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .black
        tableView.rowHeight = 18
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(doubleClickRow)
        tableView.target = self
        tableView.selectionHighlightStyle = .regular
        tableView.gridStyleMask = []
        tableView.onEnter = { [weak self] in self?.playSelectedRow() }
        tableView.onDelete = { [weak self] in self?.removeSelected() }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.backgroundColor = .black
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        // Custom scroller appearance
        scrollView.verticalScroller?.controlSize = .small
        addSubview(scrollView)

        // Skinned scroll handle (lives in the right-tile area; hidden when unskinned).
        skinScroller.attach(to: scrollView)
        skinScroller.isHidden = true
        addSubview(skinScroller)

        // Search field
        searchField.placeholderString = "Search playlist..."
        searchField.font = WinampTheme.bitrateFont
        searchField.textColor = WinampTheme.greenBright
        searchField.backgroundColor = NSColor(hex: 0x0A0E0A)
        searchField.isBordered = true
        searchField.isBezeled = true
        searchField.bezelStyle = .squareBezel
        searchField.focusRingType = .none
        searchField.delegate = self
        addSubview(searchField)

        // Buttons
        addButton.onClick = { [weak self] in self?.showAddMenu() }
        remButton.onClick = { [weak self] in self?.removeSelected() }
        remAllButton.onClick = { [weak self] in self?.playlistManager?.clearPlaylist() }

        // Sprite providers (pledit.bmp submenu sub-buttons)
        addButton.spriteKeyProvider    = { _, pressed in .playlistAddFile(pressed: pressed) }
        remButton.spriteKeyProvider    = { _, pressed in .playlistRemoveSelected(pressed: pressed) }
        remAllButton.spriteKeyProvider = { _, pressed in .playlistRemoveAll(pressed: pressed) }
        listOptsButton.spriteKeyProvider = { _, pressed in .playlistMiscOpts(pressed: pressed) }

        addSubview(addButton)
        addSubview(remButton)
        addSubview(remAllButton)

        listOptsButton.onClick = { [weak self] in self?.showListOptsMenu() }
        addSubview(listOptsButton)

        // Info label
        infoLabel.font = WinampTheme.bitrateFont
        infoLabel.textColor = WinampTheme.greenBright
        infoLabel.backgroundColor = .black
        infoLabel.drawsBackground = true
        infoLabel.isBezeled = false
        infoLabel.isEditable = false
        infoLabel.alignment = .center
        addSubview(infoLabel)

        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySkinVisibility()
                self?.tableView.reloadData()
                self?.needsDisplay = true
            }
        applySkinVisibility()
    }

    /// Hides controls baked into pledit.bmp and controls that don't exist in
    /// classic Winamp (the search field). The ADD/REM buttons are hidden because
    /// pledit's bottom-left corner sprite already paints them — showing the Wamp
    /// NSButtons on top would double-render. Classic Winamp had no persistent
    /// search bar (it used Ctrl+J Jump-To-File), so searchField hides too.
    private func applySkinVisibility() {
        let active = WinampTheme.skinIsActive
        titleBar.isHidden = active
        infoLabel.isHidden = active
        searchField.isHidden = active
        addButton.isHidden = active
        remButton.isHidden = active
        remAllButton.isHidden = active
        listOptsButton.isHidden = active
        // Classic Winamp playlist rows are tight — text.bmp glyphs are 6 px tall.
        tableView.rowHeight = active ? 13 : 18
        tableView.backgroundColor = active ? WinampTheme.provider.playlistStyle.normalBG : .black
        scrollView.backgroundColor = tableView.backgroundColor
        // Skinned playlists draw their own scroll thumb in the right-tile area.
        scrollView.hasVerticalScroller = !active
        skinScroller.isHidden = !active
        tableView.reloadData()
        needsLayout = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard WinampTheme.skinIsActive else { return }
        drawSkinned()
    }

    private func drawSkinned() {
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prev { ctx?.imageInterpolation = prev } }

        let isActive = window?.isKeyWindow ?? true
        let w = bounds.width
        let h = bounds.height

        // Top row: TL corner (25×20) + repeating top tiles + title bar centerpiece + TR corner
        if let tl = WinampTheme.sprite(.playlistTopLeftCorner(active: isActive)) {
            tl.draw(in: NSRect(x: 0, y: h - 20, width: 25, height: 20))
        }
        if let tr = WinampTheme.sprite(.playlistTopRightCorner(active: isActive)) {
            tr.draw(in: NSRect(x: w - 25, y: h - 20, width: 25, height: 20))
        }
        // Title centerpiece — fills the middle of the top row
        if let title = WinampTheme.sprite(.playlistTopTitleBar(active: isActive)) {
            let titleW: CGFloat = 100
            let titleX = (w - titleW) / 2
            title.draw(in: NSRect(x: titleX, y: h - 20, width: titleW, height: 20))
            // Tile the gap between corners and title with .playlistTopTile
            if let topTile = WinampTheme.sprite(.playlistTopTile(active: isActive)) {
                var x: CGFloat = 25
                while x < titleX {
                    topTile.draw(in: NSRect(x: x, y: h - 20, width: min(25, titleX - x), height: 20))
                    x += 25
                }
                x = titleX + titleW
                while x < w - 25 {
                    topTile.draw(in: NSRect(x: x, y: h - 20, width: min(25, w - 25 - x), height: 20))
                    x += 25
                }
            }
        }

        // Sides: tile vertically
        if let lt = WinampTheme.sprite(.playlistLeftTile) {
            var y: CGFloat = 38
            while y < h - 20 {
                lt.draw(in: NSRect(x: 0, y: y, width: 12, height: min(29, h - 20 - y)))
                y += 29
            }
        }
        if let rt = WinampTheme.sprite(.playlistRightTile) {
            var y: CGFloat = 38
            while y < h - 20 {
                rt.draw(in: NSRect(x: w - 20, y: y, width: 20, height: min(29, h - 20 - y)))
                y += 29
            }
        }

        // Bottom row
        if let bl = WinampTheme.sprite(.playlistBottomLeftCorner) {
            bl.draw(in: NSRect(x: 0, y: 0, width: 125, height: 38))
        }
        if let br = WinampTheme.sprite(.playlistBottomRightCorner) {
            br.draw(in: NSRect(x: w - 150, y: 0, width: 150, height: 38))
        }

        // Mask the mini-player buttons and ":"-timer baked into the BR corner.
        // Classic Winamp wired these to playlist-local transport; we don't need
        // them (main-window transport is the single source of truth), so paint
        // black over top-down y=18..31 × x=4..101 inside the 150×38 sprite.
        // AppKit: y=7..20. Stops short of the LIST OPTS box at x≥105 and keeps
        // the outer frame (bottom 2px, left/right edges) intact.
        NSColor.black.setFill()
        NSRect(x: w - 146, y: 7, width: 97, height: 13).fill()

        // Render the compact "N / H:MM" summary via text.bmp inside the baked
        // "running time" LCD area of the bottom-right corner sprite. The full
        // "N tracks / H:MM:SS" form overflows the ~100px LCD once counts or
        // durations grow — drop the "tracks" label and the seconds so track
        // counts into the hundreds still fit.
        // Webamp positions #playlist-running-time-display at top:10, left:7
        // inside the 150×38 BR corner, i.e. absolute (w-150+7, corner-top-10).
        if let textSheet = WinampTheme.provider.textSheet, let pm = playlistManager {
            let info = "\(pm.tracks.count) / \(pm.formattedTotalDurationCompact)"
            let textX = w - 150 + 7
            let textY: CGFloat = 38 - 10 - TextSpriteRenderer.glyphHeight
            TextSpriteRenderer.draw(info, at: NSPoint(x: textX, y: textY), sheet: textSheet)
        }
    }

    override func layout() {
        super.layout()
        if WinampTheme.skinIsActive {
            layoutSkinned()
            return
        }
        layoutUnskinned()
    }

    /// Classic-Winamp pledit frame layout: 20px title bar at top, 38px bottom
    /// corner strip (ADD/REM baked in), 12px left tile, 20px right tile.
    /// The track list fills the middle.
    private func layoutSkinned() {
        let w = bounds.width
        let h = bounds.height
        let topH: CGFloat = 20
        let bottomH: CGFloat = 38
        let leftW: CGFloat = 12
        let rightW: CGFloat = 20

        titleBar.frame = NSRect(x: 0, y: h - topH, width: w, height: topH)
        scrollView.frame = NSRect(
            x: leftW,
            y: bottomH,
            width: w - leftW - rightW,
            height: h - topH - bottomH
        )

        // Hidden in skinned mode — collapse frames so they don't intercept hits.
        searchField.frame = .zero
        addButton.frame = .zero
        remButton.frame = .zero
        remAllButton.frame = .zero
        listOptsButton.frame = .zero
        infoLabel.frame = .zero

        // Native scroller is hidden in skinned mode — full column width.
        let newWidth = scrollView.frame.width - 2
        tableView.tableColumns.first?.width = newWidth
        if abs(newWidth - lastColumnWidth) > 0.5 {
            lastColumnWidth = newWidth
            tableView.reloadData()
        }

        // Skin scroll thumb sits in the right-tile area, centered horizontally
        // within the 20px tile. Track height matches the right-tile vertical span.
        let trackTop = h - topH
        let trackBottom = bottomH
        let trackH = max(0, trackTop - trackBottom)
        skinScroller.frame = NSRect(x: w - 20 + 6, y: trackBottom, width: 8, height: trackH)
    }

    private func layoutUnskinned() {
        let w = bounds.width
        let pad: CGFloat = 3

        titleBar.frame = NSRect(x: 0, y: bounds.height - WinampTheme.titleBarHeight,
                                width: w, height: WinampTheme.titleBarHeight)

        let bottomBarH: CGFloat = 18
        let searchH: CGFloat = 16

        // Bottom bar
        let btnW: CGFloat = 30
        let btnH: CGFloat = 14
        addButton.frame = NSRect(x: pad, y: 2, width: btnW, height: btnH)
        remButton.frame = NSRect(x: pad + btnW + 1, y: 2, width: btnW, height: btnH)
        remAllButton.frame = NSRect(x: pad + (btnW + 1) * 2, y: 2, width: btnW, height: btnH)

        let listOptsW: CGFloat = 36
        listOptsButton.frame = NSRect(x: w - pad - listOptsW, y: 2, width: listOptsW, height: btnH)

        let infoW: CGFloat = 90
        let infoFont = infoLabel.font ?? NSFont.systemFont(ofSize: 9)
        let infoTextH = infoFont.boundingRectForFont.height
        let infoY = round((bottomBarH - infoTextH) / 2)
        infoLabel.frame = NSRect(x: w - pad - listOptsW - 4 - infoW, y: infoY, width: infoW, height: infoTextH)

        // Search
        searchField.frame = NSRect(x: pad, y: bottomBarH, width: w - 2 * pad, height: searchH)

        // Scroll view
        let scrollTop = bounds.height - WinampTheme.titleBarHeight
        let scrollH = scrollTop - bottomBarH - searchH - 2
        scrollView.frame = NSRect(x: pad, y: bottomBarH + searchH + 1, width: w - 2 * pad, height: scrollH)

        let scrollerWidth = scrollView.verticalScroller?.frame.width ?? 15
        let newWidth = scrollView.frame.width - scrollerWidth - 2
        tableView.tableColumns.first?.width = newWidth
        if abs(newWidth - lastColumnWidth) > 0.5 {
            lastColumnWidth = newWidth
            tableView.reloadData()
        }
    }

    func bindToModel(playlistManager: PlaylistManager) {
        self.playlistManager = playlistManager

        playlistManager.$tracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
                self?.updateInfoLabel()
            }
            .store(in: &cancellables)

        playlistManager.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                guard let self, let pm = self.playlistManager else { return }
                self.tableView.reloadData()
                if index >= 0, index < pm.tracks.count {
                    let currentTrack = pm.tracks[index]
                    let displayed = pm.filteredTracks
                    if let displayRow = displayed.firstIndex(where: { $0.id == currentTrack.id }) {
                        self.tableView.selectRowIndexes(IndexSet(integer: displayRow), byExtendingSelection: false)
                        self.tableView.scrollRowToVisible(displayRow)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func updateInfoLabel() {
        guard let pm = playlistManager else { return }
        infoLabel.stringValue = "\(pm.tracks.count) / \(pm.formattedTotalDurationCompact)"
    }

    @objc private func doubleClickRow() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        playRow(row)
    }

    private func playSelectedRow() {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        playRow(row)
    }

    private func playRow(_ row: Int) {
        let tracks = displayedTracks
        guard row < tracks.count else { return }
        if let realIndex = playlistManager?.tracks.firstIndex(where: { $0.id == tracks[row].id }) {
            playlistManager?.playTrack(at: realIndex)
        }
    }

    private func removeSelected() {
        let tracks = displayedTracks
        let realIndices = tableView.selectedRowIndexes.compactMap { row -> Int? in
            guard row < tracks.count else { return nil }
            return playlistManager?.tracks.firstIndex(where: { $0.id == tracks[row].id })
        }.sorted().reversed()
        for index in realIndices {
            playlistManager?.removeTrack(at: index)
        }
    }

    // MARK: - Skinned bottom-bar handlers
    private func handleSkinnedAdd() {
        let menu = NSMenu()
        let fileItem = NSMenuItem(title: "Add Files...", action: #selector(addFiles), keyEquivalent: "")
        fileItem.target = self
        let folderItem = NSMenuItem(title: "Add Folder...", action: #selector(addFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(fileItem)
        menu.addItem(folderItem)
        menu.popUp(positioning: nil, at: NSPoint(x: Self.skinnedAddRect.minX, y: Self.skinnedAddRect.maxY), in: self)
    }

    private func handleSkinnedRem() {
        let menu = NSMenu()
        let remSel = NSMenuItem(title: "Remove Selected", action: #selector(remMenuRemoveSelected), keyEquivalent: "")
        remSel.target = self
        let remAll = NSMenuItem(title: "Remove All", action: #selector(remMenuRemoveAll), keyEquivalent: "")
        remAll.target = self
        menu.addItem(remSel)
        menu.addItem(remAll)
        menu.popUp(positioning: nil, at: NSPoint(x: Self.skinnedRemRect.minX, y: Self.skinnedRemRect.maxY), in: self)
    }

    @objc private func remMenuRemoveSelected() { removeSelected() }
    @objc private func remMenuRemoveAll() { playlistManager?.clearPlaylist() }

    private func handleSkinnedSel() {
        let menu = NSMenu()
        let selAll = NSMenuItem(title: "Select All", action: #selector(selMenuSelectAll), keyEquivalent: "")
        selAll.target = self
        let selNone = NSMenuItem(title: "Select None", action: #selector(selMenuSelectNone), keyEquivalent: "")
        selNone.target = self
        let selInvert = NSMenuItem(title: "Invert Selection", action: #selector(selMenuInvert), keyEquivalent: "")
        selInvert.target = self
        menu.addItem(selAll)
        menu.addItem(selNone)
        menu.addItem(selInvert)
        menu.popUp(positioning: nil, at: NSPoint(x: Self.skinnedSelRect.minX, y: Self.skinnedSelRect.maxY), in: self)
    }

    @objc private func selMenuSelectAll() {
        let count = tableView.numberOfRows
        guard count > 0 else { return }
        tableView.selectRowIndexes(IndexSet(0..<count), byExtendingSelection: false)
    }
    @objc private func selMenuSelectNone() {
        tableView.deselectAll(nil)
    }
    @objc private func selMenuInvert() {
        let all = IndexSet(0..<tableView.numberOfRows)
        let current = tableView.selectedRowIndexes
        tableView.selectRowIndexes(all.symmetricDifference(current), byExtendingSelection: false)
    }

    private func showAddMenu() {
        let menu = NSMenu()
        let fileItem = NSMenuItem(title: "Add Files...", action: #selector(addFiles), keyEquivalent: "")
        fileItem.target = self
        let folderItem = NSMenuItem(title: "Add Folder...", action: #selector(addFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(fileItem)
        menu.addItem(folderItem)
        menu.popUp(positioning: nil, at: NSPoint(x: addButton.frame.minX, y: addButton.frame.maxY), in: self)
    }

    @objc private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                await self?.playlistManager?.addURLs(panel.urls)
            }
        }
    }

    private func showListOptsMenu() {
        let menu = NSMenu()
        let newItem = NSMenuItem(title: "New list", action: #selector(listOptsNew), keyEquivalent: "")
        newItem.target = self
        let loadItem = NSMenuItem(title: "Load list…", action: #selector(listOptsLoad), keyEquivalent: "")
        loadItem.target = self
        let saveItem = NSMenuItem(title: "Save list…", action: #selector(listOptsSave), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(newItem)
        menu.addItem(loadItem)
        menu.addItem(saveItem)
        let anchor: NSPoint
        if WinampTheme.skinIsActive {
            let r = skinnedListOptsRect()
            anchor = NSPoint(x: r.minX, y: r.maxY)
        } else {
            anchor = NSPoint(x: listOptsButton.frame.minX, y: listOptsButton.frame.maxY)
        }
        menu.popUp(positioning: nil, at: anchor, in: self)
    }

    @objc private func listOptsNew() {
        playlistManager?.clearPlaylist()
    }

    @objc private func listOptsLoad() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u"),
                                     UTType(filenameExtension: "m3u8"),
                                     UTType(filenameExtension: "pls")].compactMap { $0 }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.playlistManager?.loadPlaylistM3U(from: url)
            }
        }
    }

    @objc private func listOptsSave() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u")].compactMap { $0 }
        panel.nameFieldStringValue = "playlist.m3u"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.playlistManager?.savePlaylistM3U(to: url)
        }
    }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.playlistManager?.addFolder(url)
            }
        }
    }

    // MARK: - Skinned bottom-button rects
    // Baked-button positions measured from PLEDIT.BMP bottom-left corner sprite
    // (125×38 drawn at playlist y=0). AppKit y = 10 places the 18px-tall buttons
    // flush with the visible baked graphics (sprite y_topdown ≈ 10..28).
    private static let skinnedAddRect  = NSRect(x: 11, y: 10, width: 22, height: 18)
    private static let skinnedRemRect  = NSRect(x: 40, y: 10, width: 22, height: 18)
    private static let skinnedSelRect  = NSRect(x: 69, y: 10, width: 22, height: 18)

    // LIST OPTS lives in the bottom-right corner (150×38 at x=w-150).
    // Bounds measured directly from pledit.bmp BR-corner pixels: the visible
    // raised box spans top-down (105, 8, 23, 18) → playlist-local x = w-45,
    // AppKit y = 38 - 8 - 18 = 12.
    private func skinnedListOptsRect() -> NSRect {
        NSRect(x: bounds.width - 45, y: 12, width: 23, height: 18)
    }

    // MARK: - Mouse handling (skinned mode: dragging + bottom buttons)
    override func mouseDown(with event: NSEvent) {
        guard WinampTheme.skinIsActive else { super.mouseDown(with: event); return }
        let point = convert(event.locationInWindow, from: nil)

        // Title bar drag zone (top 20px)
        if point.y >= bounds.height - 20 {
            dragOrigin = event.locationInWindow
            return
        }

        // Bottom button strip. MISC sprite is baked into the BL corner but is
        // intentionally inert — list management lives under LIST OPTS only.
        if point.y < 38 {
            if Self.skinnedAddRect.contains(point) { handleSkinnedAdd(); return }
            if Self.skinnedRemRect.contains(point) { handleSkinnedRem(); return }
            if Self.skinnedSelRect.contains(point) { handleSkinnedSel(); return }
            if skinnedListOptsRect().contains(point) { showListOptsMenu(); return }
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let win = window else {
            super.mouseDragged(with: event)
            return
        }
        let current = event.locationInWindow
        var frame = win.frame
        frame.origin.x += current.x - origin.x
        frame.origin.y += current.y - origin.y
        win.setFrameOrigin(frame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        super.mouseUp(with: event)
    }

    // MARK: - Drag and Drop
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        Task { @MainActor in
            for url in items {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue {
                    await playlistManager?.addFolder(url)
                } else {
                    await playlistManager?.addURLs([url])
                }
            }
        }
        return true
    }
}

// MARK: - NSTableViewDataSource / Delegate
extension PlaylistView: NSTableViewDataSource, NSTableViewDelegate {
    private var displayedTracks: [Track] {
        playlistManager?.filteredTracks ?? []
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedTracks.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let tracks = displayedTracks
        guard row < tracks.count else { return nil }
        let track = tracks[row]
        let isPlaying = playlistManager?.currentTrack?.id == track.id
        let skinned = WinampTheme.skinIsActive

        let rowH: CGFloat = tableView.rowHeight
        let cellW = tableColumn?.width ?? 200
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: cellW, height: rowH))
        cell.autoresizesSubviews = true

        let font: NSFont = skinned
            ? (NSFont(name: WinampTheme.provider.playlistStyle.font, size: 7) ?? NSFont.systemFont(ofSize: 7))
            : WinampTheme.playlistFont
        let textH = font.boundingRectForFont.height
        let yOffset = round((rowH - textH) / 2)

        let style = WinampTheme.provider.playlistStyle
        let normalColor = skinned ? style.normal  : WinampTheme.greenBright
        let currentColor = skinned ? style.current : WinampTheme.white
        let secondaryColor = skinned ? style.normal : WinampTheme.greenSecondary

        // Number
        let numStr = "\(row + 1)."
        let numLabel = NSTextField(labelWithString: numStr)
        numLabel.font = font
        numLabel.textColor = isPlaying ? currentColor : secondaryColor
        numLabel.isBezeled = false
        numLabel.drawsBackground = false
        numLabel.sizeToFit()
        let numWidth = numLabel.frame.width
        numLabel.frame = NSRect(x: -10, y: yOffset, width: numWidth, height: textH)
        cell.addSubview(numLabel)

        // Duration
        let durLabel = NSTextField(labelWithString: track.formattedDuration)
        durLabel.font = font
        durLabel.textColor = isPlaying ? currentColor : secondaryColor
        durLabel.isBezeled = false
        durLabel.drawsBackground = false
        durLabel.sizeToFit()
        // sizeToFit underestimates width for small Arial — pad the label so the
        // trailing digit isn't clipped inside its own frame.
        let durWidth = durLabel.frame.width + 3
        let rightMargin: CGFloat = 10
        durLabel.frame = NSRect(x: cellW - durWidth - rightMargin, y: yOffset, width: durWidth, height: textH)
        cell.addSubview(durLabel)

        // Track name
        let nameX = numWidth - 10 + 4
        let nameLabel = NSTextField(labelWithString: track.displayTitle)
        nameLabel.font = font
        nameLabel.textColor = isPlaying ? currentColor : normalColor
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: nameX, y: yOffset, width: cellW - nameX - durWidth - rightMargin - 4, height: textH)
        cell.addSubview(nameLabel)

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = WinampRowView()
        return rowView
    }

    // MARK: - Internal Drag & Drop Reordering
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        // Disable reordering while search is active
        guard playlistManager?.searchQuery.isEmpty == true else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: PlaylistView.internalRowType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // Accept file drops as copy
        if info.draggingPasteboard.types?.contains(.fileURL) == true,
           info.draggingSource as? NSTableView !== tableView {
            return .copy
        }
        // Internal reorder: only between rows, not on rows
        if dropOperation == .above {
            return .move
        }
        return []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        // Handle external file drops
        if let source = info.draggingSource as? NSTableView, source === tableView {
            // Internal reorder
            var sourceIndexes = IndexSet()
            info.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                if let pasteboardItem = item.item as? NSPasteboardItem,
                   let rowStr = pasteboardItem.string(forType: PlaylistView.internalRowType),
                   let sourceRow = Int(rowStr) {
                    sourceIndexes.insert(sourceRow)
                }
            }
            playlistManager?.moveTracks(from: sourceIndexes, to: row)
            return true
        }

        // External file drop on table
        guard let items = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        Task { @MainActor in
            for url in items {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue {
                    await playlistManager?.addFolder(url)
                } else {
                    await playlistManager?.addURLs([url])
                }
            }
        }
        return true
    }
}

// MARK: - Custom table view with Enter-to-play
class PlaylistTableView: NSTableView {
    var onEnter: (() -> Void)?
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return key
            onEnter?()
        } else if event.keyCode == 51 { // Backspace key
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// Custom row view with Winamp-style blue selection
class WinampRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        if isSelected {
            WinampTheme.selectionBlue.setFill()
            bounds.fill()
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
    }
}

// MARK: - Search
extension PlaylistView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        playlistManager?.searchQuery = searchField.stringValue
        tableView.reloadData()
    }
}
