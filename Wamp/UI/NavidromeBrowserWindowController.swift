import AppKit
import Combine

/// "Media Library" style window for a Navidrome server: browse by artist,
/// playlist, recently added, random or starred; search the whole library;
/// then Play (replace the playlist) or Enqueue (append) the songs. Songs
/// become remote `Track`s that `PlaylistManager` streams through the stream
/// cache — the window never touches `AudioEngine` directly.
@MainActor
final class NavidromeBrowserWindowController: NSWindowController, NSWindowDelegate {

    /// (tracks, replacePlaylist, startPlaying). Routed by AppDelegate.
    var onAddTracks: (([Track], _ replace: Bool, _ play: Bool) -> Void)?
    var onOpenSettings: (() -> Void)?

    enum Mode: Int, CaseIterable {
        case artists, playlists, recentlyAdded, random, starred
        var title: String {
            switch self {
            case .artists: return "Artists"
            case .playlists: return "Playlists"
            case .recentlyAdded: return "Recently Added"
            case .random: return "Random Albums"
            case .starred: return "Starred"
            }
        }
    }

    private enum LeftItem {
        case artist(SubsonicArtist)
        case playlist(SubsonicPlaylist)
        var title: String {
            switch self {
            case .artist(let a): return a.name
            case .playlist(let p): return p.name
            }
        }
        var subtitle: String {
            switch self {
            case .artist(let a):
                let n = a.albumCount ?? 0
                return n == 1 ? "1 album" : "\(n) albums"
            case .playlist(let p):
                let n = p.songCount ?? 0
                return n == 1 ? "1 song" : "\(n) songs"
            }
        }
    }

    // MARK: - State

    private let service: NavidromeService
    private var cancellables = Set<AnyCancellable>()
    private var mode: Mode = .artists
    private var leftItems: [LeftItem] = []
    private var albums: [SubsonicAlbum] = []
    private var songs: [SubsonicSong] = []
    private var loadGeneration = 0
    private var searchTask: Task<Void, Never>?

    // MARK: - UI

    private let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let searchField = NSSearchField()
    private let settingsButton = NSButton(title: "Server…", target: nil, action: nil)
    private let leftTable = NSTableView()
    private let albumTable = NSTableView()
    private let songTable = NSTableView()
    private let leftScroll = NSScrollView()
    private let albumScroll = NSScrollView()
    private let songScroll = NSScrollView()
    private let leftHeader = NSTextField(labelWithString: "ARTISTS")
    private let albumHeader = NSTextField(labelWithString: "ALBUMS")
    private let songHeader = NSTextField(labelWithString: "SONGS")
    private let leftColumn = NSStackView()
    private let albumColumn = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let enqueueButton = NSButton(title: "Enqueue", target: nil, action: nil)
    private let playButton = NSButton(title: "Play", target: nil, action: nil)

    private static let leftID = NSUserInterfaceItemIdentifier("left")
    private static let albumID = NSUserInterfaceItemIdentifier("album")

    // MARK: - Init

    init(service: NavidromeService) {
        self.service = service
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 580),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        w.title = "Navidrome Library"
        w.minSize = NSSize(width: 720, height: 400)
        w.setFrameAutosaveName("NavidromeBrowser")
        super.init(window: w)
        w.delegate = self
        buildLayout()

        service.$client
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.connectionChanged() }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }

        for m in Mode.allCases { modePopup.addItem(withTitle: m.title) }
        modePopup.target = self
        modePopup.action = #selector(modeChanged)

        searchField.placeholderString = "Search artists, albums, songs"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = false
        (searchField.cell as? NSSearchFieldCell)?.sendsSearchStringImmediately = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        settingsButton.target = self
        settingsButton.action = #selector(settingsPressed)

        let topBar = NSStackView(views: [modePopup, NSView(), searchField, settingsButton])
        topBar.orientation = .horizontal
        topBar.spacing = 10

        configureListTable(leftTable, identifier: Self.leftID, scroll: leftScroll)
        configureListTable(albumTable, identifier: Self.albumID, scroll: albumScroll)
        configureSongTable()

        leftTable.doubleAction = #selector(leftDoubleClicked)
        albumTable.doubleAction = #selector(albumDoubleClicked)
        songTable.doubleAction = #selector(songDoubleClicked)
        for t in [leftTable, albumTable, songTable] { t.target = self }

        for h in [leftHeader, albumHeader, songHeader] {
            h.font = NSFont.boldSystemFont(ofSize: 10)
            h.textColor = .secondaryLabelColor
        }

        func column(_ stack: NSStackView, header: NSTextField, scroll: NSScrollView) {
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 4
            stack.addArrangedSubview(header)
            stack.addArrangedSubview(scroll)
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let songColumn = NSStackView()
        column(leftColumn, header: leftHeader, scroll: leftScroll)
        column(albumColumn, header: albumHeader, scroll: albumScroll)
        column(songColumn, header: songHeader, scroll: songScroll)

        let columns = NSStackView(views: [leftColumn, albumColumn, songColumn])
        columns.orientation = .horizontal
        columns.distribution = .fill
        columns.spacing = 12
        columns.setHuggingPriority(.defaultLow, for: .vertical)
        leftColumn.widthAnchor.constraint(equalToConstant: 200).isActive = true
        albumColumn.widthAnchor.constraint(equalToConstant: 220).isActive = true
        songColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
        songColumn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true

        enqueueButton.target = self
        enqueueButton.action = #selector(enqueuePressed)
        enqueueButton.toolTip = "Append the selected songs (or every listed song) to the playlist"
        playButton.target = self
        playButton.action = #selector(playPressed)
        playButton.keyEquivalent = "\r"
        playButton.toolTip = "Replace the playlist with the selected songs (or every listed song) and start playing"

        let bottomBar = NSStackView(views: [spinner, statusLabel, NSView(), enqueueButton, playButton])
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 10
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let root = NSStackView(views: [topBar, columns, bottomBar])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            topBar.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32),
            columns.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32),
            bottomBar.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32),
        ])
    }

    private func configureListTable(_ table: NSTableView, identifier: NSUserInterfaceItemIdentifier, scroll: NSScrollView) {
        table.headerView = nil
        table.rowHeight = 22
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.style = .inset
        let col = NSTableColumn(identifier: identifier)
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureSongTable() {
        let t = songTable
        t.rowHeight = 20
        t.allowsMultipleSelection = true
        t.allowsEmptySelection = true
        t.usesAlternatingRowBackgroundColors = true
        t.style = .inset
        t.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let specs: [(String, String, CGFloat)] = [
            ("track", "#", 32), ("title", "Title", 260), ("artist", "Artist", 160),
            ("album", "Album", 180), ("time", "Time", 48),
        ]
        for (id, title, width) in specs {
            let col = NSTableColumn(identifier: .init(id))
            col.title = title
            col.width = width
            col.minWidth = 28
            t.addTableColumn(col)
        }
        t.dataSource = self
        t.delegate = self
        songScroll.documentView = t
        songScroll.hasVerticalScroller = true
        songScroll.hasHorizontalScroller = true
        songScroll.borderType = .bezelBorder
        songScroll.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Presentation

    func present() {
        guard let window else { return }
        if !window.isVisible {
            if window.frameAutosaveName.isEmpty || !window.setFrameUsingName("NavidromeBrowser") {
                window.center()
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        if leftItems.isEmpty && albums.isEmpty && songs.isEmpty {
            reload()
        }
    }

    private func connectionChanged() {
        leftItems = []
        albums = []
        songs = []
        reloadTables()
        if service.isConfigured {
            reload()
        } else {
            setStatus("Not connected. Click Server… to add your Navidrome login.")
        }
    }

    // MARK: - Loading

    private func nextGeneration() -> Int {
        loadGeneration += 1
        return loadGeneration
    }

    private func setBusy(_ busy: Bool) {
        spinner.isHidden = !busy
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.textColor = .secondaryLabelColor
    }

    private func setError(_ error: Error) {
        setBusy(false)
        let ns = error as NSError
        let text = (error as? SubsonicError)?.localizedDescription ?? ns.localizedDescription
        statusLabel.stringValue = "Error: \(text)"
        statusLabel.textColor = .systemRed
    }

    private func connectedStatus(_ detail: String) -> String {
        if let c = service.credentials {
            return "\(c.username)@\(c.displayHost) · \(detail)"
        }
        return detail
    }

    /// Reload the current mode (or the current search) from scratch.
    private func reload() {
        if !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            runSearch(searchField.stringValue)
            return
        }
        guard let client = service.client else { return }
        let gen = nextGeneration()
        leftItems = []; albums = []; songs = []
        applyColumnVisibility(forSearch: false)
        reloadTables()
        setBusy(true)
        setStatus(connectedStatus("Loading \(mode.title.lowercased())…"))
        let mode = self.mode
        Task { @MainActor in
            do {
                switch mode {
                case .artists:
                    let list = try await client.artists()
                    guard gen == loadGeneration else { return }
                    leftItems = list.map { .artist($0) }
                    setStatus(connectedStatus("\(list.count) artists"))
                case .playlists:
                    let list = try await client.playlists()
                    guard gen == loadGeneration else { return }
                    leftItems = list.map { .playlist($0) }
                    setStatus(connectedStatus("\(list.count) playlists"))
                case .recentlyAdded:
                    albums = try await client.albumList(.newest, size: 200)
                    guard gen == loadGeneration else { return }
                    setStatus(connectedStatus("\(albums.count) recently added albums"))
                case .random:
                    albums = try await client.albumList(.random, size: 100)
                    guard gen == loadGeneration else { return }
                    setStatus(connectedStatus("\(albums.count) random albums — pick the mode again to reshuffle"))
                case .starred:
                    let starred = try await client.starred()
                    guard gen == loadGeneration else { return }
                    albums = starred.album ?? []
                    songs = starred.song ?? []
                    setStatus(connectedStatus("\(albums.count) starred albums, \(songs.count) starred songs"))
                }
                setBusy(false)
                reloadTables()
            } catch {
                guard gen == loadGeneration else { return }
                setError(error)
            }
        }
    }

    private func runSearch(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespaces)
        guard let client = service.client, !query.isEmpty else { return }
        let gen = nextGeneration()
        applyColumnVisibility(forSearch: true)
        setBusy(true)
        setStatus(connectedStatus("Searching for “\(query)”…"))
        Task { @MainActor in
            do {
                let result = try await client.search(query)
                guard gen == loadGeneration else { return }
                leftItems = (result.artist ?? []).map { .artist($0) }
                albums = result.album ?? []
                songs = result.song ?? []
                setBusy(false)
                setStatus(connectedStatus("\(leftItems.count) artists, \(albums.count) albums, \(songs.count) songs match"))
                reloadTables()
            } catch {
                guard gen == loadGeneration else { return }
                setError(error)
            }
        }
    }

    private func loadAlbums(forArtist artist: SubsonicArtist) {
        guard let client = service.client else { return }
        let gen = nextGeneration()
        albums = []; songs = []
        albumTable.reloadData(); songTable.reloadData()
        setBusy(true)
        Task { @MainActor in
            do {
                let full = try await client.artist(id: artist.id)
                guard gen == loadGeneration else { return }
                albums = (full.album ?? []).sorted { ($0.year ?? 0, $0.name) < ($1.year ?? 0, $1.name) }
                setBusy(false)
                setStatus(connectedStatus("\(artist.name): \(albums.count) albums"))
                albumTable.reloadData()
            } catch {
                guard gen == loadGeneration else { return }
                setError(error)
            }
        }
    }

    private func loadSongs(forAlbum album: SubsonicAlbum, then completion: (([SubsonicSong]) -> Void)? = nil) {
        guard let client = service.client else { return }
        let gen = nextGeneration()
        if completion == nil { songs = []; songTable.reloadData() }
        setBusy(true)
        Task { @MainActor in
            do {
                let full = try await client.album(id: album.id)
                guard gen == loadGeneration else { return }
                let list = full.song ?? []
                setBusy(false)
                if let completion {
                    completion(list)
                } else {
                    songs = list
                    setStatus(connectedStatus("\(album.name): \(songs.count) songs"))
                    songTable.reloadData()
                }
            } catch {
                guard gen == loadGeneration else { return }
                setError(error)
            }
        }
    }

    private func loadSongs(forPlaylist playlist: SubsonicPlaylist) {
        guard let client = service.client else { return }
        let gen = nextGeneration()
        songs = []; songTable.reloadData()
        setBusy(true)
        Task { @MainActor in
            do {
                let full = try await client.playlist(id: playlist.id)
                guard gen == loadGeneration else { return }
                songs = full.entry ?? []
                setBusy(false)
                setStatus(connectedStatus("\(playlist.name): \(songs.count) songs"))
                songTable.reloadData()
            } catch {
                guard gen == loadGeneration else { return }
                setError(error)
            }
        }
    }

    private func applyColumnVisibility(forSearch searching: Bool) {
        let showLeft = searching || mode == .artists || mode == .playlists
        let showAlbums = searching || mode != .playlists
        leftColumn.isHidden = !showLeft
        albumColumn.isHidden = !showAlbums
        leftHeader.stringValue = (mode == .playlists && !searching) ? "PLAYLISTS" : "ARTISTS"
    }

    private func reloadTables() {
        leftTable.reloadData()
        albumTable.reloadData()
        songTable.reloadData()
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        mode = Mode(rawValue: modePopup.indexOfSelectedItem) ?? .artists
        searchField.stringValue = ""
        reload()
    }

    @objc private func searchChanged() {
        searchTask?.cancel()
        let text = searchField.stringValue
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            reload()
            return
        }
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            runSearch(text)
        }
    }

    @objc private func settingsPressed() { onOpenSettings?() }

    @objc private func leftDoubleClicked() {
        let row = leftTable.clickedRow
        guard row >= 0, row < leftItems.count else { return }
        switch leftItems[row] {
        case .artist(let artist):
            // Enqueue the artist's whole catalogue in album order.
            enqueueAllAlbums(of: artist)
        case .playlist(let playlist):
            guard let client = service.client else { return }
            Task { @MainActor in
                if let full = try? await client.playlist(id: playlist.id) {
                    emit(full.entry ?? [], replace: false, play: true)
                }
            }
        }
    }

    @objc private func albumDoubleClicked() {
        let row = albumTable.clickedRow
        guard row >= 0, row < albums.count else { return }
        loadSongs(forAlbum: albums[row]) { [weak self] list in
            self?.emit(list, replace: false, play: true)
        }
    }

    @objc private func songDoubleClicked() {
        let row = songTable.clickedRow
        guard row >= 0, row < songs.count else { return }
        emit([songs[row]], replace: false, play: true)
    }

    @objc private func enqueuePressed() {
        emit(selectedOrAllSongs(), replace: false, play: false)
    }

    @objc private func playPressed() {
        emit(selectedOrAllSongs(), replace: true, play: true)
    }

    private func selectedOrAllSongs() -> [SubsonicSong] {
        let sel = songTable.selectedRowIndexes
        if sel.isEmpty { return songs }
        return sel.compactMap { $0 < songs.count ? songs[$0] : nil }
    }

    private func enqueueAllAlbums(of artist: SubsonicArtist) {
        guard let client = service.client else { return }
        setBusy(true)
        Task { @MainActor in
            do {
                let full = try await client.artist(id: artist.id)
                let sorted = (full.album ?? []).sorted { ($0.year ?? 0, $0.name) < ($1.year ?? 0, $1.name) }
                var all: [SubsonicSong] = []
                for album in sorted {
                    all += try await client.album(id: album.id).song ?? []
                }
                setBusy(false)
                emit(all, replace: false, play: true)
            } catch {
                setError(error)
            }
        }
    }

    private func emit(_ list: [SubsonicSong], replace: Bool, play: Bool) {
        guard !list.isEmpty else { return }
        let tracks = list.map { service.makeTrack($0) }
        onAddTracks?(tracks, replace, play)
        let verb = replace ? "Playing" : "Enqueued"
        setStatus(connectedStatus("\(verb) \(tracks.count) \(tracks.count == 1 ? "song" : "songs")"))
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        searchTask?.cancel()
    }
}

// MARK: - Tables

extension NavidromeBrowserWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        switch tableView {
        case leftTable: return leftItems.count
        case albumTable: return albums.count
        default: return songs.count
        }
    }

    private func label(_ text: String, secondary: Bool = false, size: CGFloat = 12) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size)
        l.lineBreakMode = .byTruncatingTail
        l.textColor = secondary ? .secondaryLabelColor : .labelColor
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func twoLineCell(title: String, subtitle: String) -> NSView {
        let container = NSStackView(views: [label(title), NSView(), label(subtitle, secondary: true, size: 10)])
        container.orientation = .horizontal
        container.spacing = 6
        container.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 4)
        return container
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch tableView {
        case leftTable:
            guard row < leftItems.count else { return nil }
            let item = leftItems[row]
            return twoLineCell(title: item.title, subtitle: item.subtitle)
        case albumTable:
            guard row < albums.count else { return nil }
            let a = albums[row]
            var sub = a.year.map(String.init) ?? ""
            if mode != .artists || !searchField.stringValue.isEmpty, let artist = a.artist, !artist.isEmpty {
                sub = sub.isEmpty ? artist : "\(artist) · \(sub)"
            }
            return twoLineCell(title: a.name, subtitle: sub)
        default:
            guard row < songs.count, let id = tableColumn?.identifier.rawValue else { return nil }
            let s = songs[row]
            let text: String
            switch id {
            case "track": text = s.track.map(String.init) ?? ""
            case "title": text = s.title
            case "artist": text = s.artist ?? ""
            case "album": text = s.album ?? ""
            case "time":
                let secs = Int(s.duration ?? 0)
                text = "\(secs / 60):" + String(format: "%02d", secs % 60)
            default: text = ""
            }
            let cell = label(text, secondary: id == "track" || id == "time")
            cell.alignment = (id == "track" || id == "time") ? .right : .left
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        switch table {
        case leftTable:
            let row = leftTable.selectedRow
            guard row >= 0, row < leftItems.count else { return }
            switch leftItems[row] {
            case .artist(let artist): loadAlbums(forArtist: artist)
            case .playlist(let playlist): loadSongs(forPlaylist: playlist)
            }
        case albumTable:
            let row = albumTable.selectedRow
            guard row >= 0, row < albums.count else { return }
            loadSongs(forAlbum: albums[row])
        default:
            break
        }
    }
}
