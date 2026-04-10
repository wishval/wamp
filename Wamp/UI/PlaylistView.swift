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
    private let remAllButton = WinampButton(title: "REM ALL", style: .action)
    private let infoLabel = NSTextField(labelWithString: "")
    private let skinScroller = PlaylistSkinScroller()

    private var cancellables = Set<AnyCancellable>()
    private var skinObserver: AnyCancellable?
    private weak var playlistManager: PlaylistManager?
    private var lastColumnWidth: CGFloat = 0

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

        addSubview(addButton)
        addSubview(remButton)
        addSubview(remAllButton)

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

        // Render "N tracks / total duration" via text.bmp inside the baked
        // "running time" LCD area of the bottom-right corner sprite.
        // Webamp positions #playlist-running-time-display at top:10, left:7
        // inside the 150×38 BR corner, i.e. absolute (w-150+7, corner-top-10).
        if let textSheet = WinampTheme.provider.textSheet, let pm = playlistManager {
            let info = "\(pm.tracks.count) tracks / \(pm.formattedTotalDuration)"
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

        let infoW: CGFloat = 100
        let infoFont = infoLabel.font ?? NSFont.systemFont(ofSize: 9)
        let infoTextH = infoFont.boundingRectForFont.height
        let infoY = round((bottomBarH - infoTextH) / 2)
        infoLabel.frame = NSRect(x: w - pad - infoW, y: infoY, width: infoW, height: infoTextH)

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
        infoLabel.stringValue = "\(pm.tracks.count) tracks / \(pm.formattedTotalDuration)"
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
