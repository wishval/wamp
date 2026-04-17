import AppKit

/// Sheet that shows the Music.app library and lets the user pick sources
/// (all songs + individual playlists) to import into Wamp. State machine:
/// loading → loaded | error. On import, the caller-supplied `onImport`
/// closure receives the concatenated ITunesTrack list so routing into
/// `PlaylistManager.importMusicLibraryTracks` stays in `AppDelegate`.
@MainActor
final class ImportMusicLibraryWindowController: NSWindowController, NSWindowDelegate {

    enum Destination { case newPlaylist, appendToCurrent }

    /// Called with (selectedTracks, destination) when the user clicks Import.
    /// The controller does NOT close the sheet itself — the caller should
    /// call `close()` after showing any follow-up alert, so the alert
    /// attaches to the parent window rather than the sheet.
    var onImport: (([ITunesTrack], Destination) -> Void)?
    /// Called when the user clicks Cancel or closes the window.
    var onCancel: (() -> Void)?

    // MARK: - Row model

    private enum Row {
        case allSongs(count: Int)
        case sectionHeader(String)
        case playlist(ITunesPlaylist, count: Int)

        var isCheckable: Bool {
            if case .sectionHeader = self { return false }
            return true
        }
    }

    private enum Source: Hashable {
        case allSongs
        case playlist(id: Int)
    }

    // MARK: - State

    private var library: ITunesLibrary?
    private var rows: [Row] = []
    private var selected: Set<Source> = [.allSongs]
    private var destination: Destination = .appendToCurrent

    // MARK: - UI

    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let newPlaylistRadio = NSButton(radioButtonWithTitle: "New playlist",
                                            target: nil, action: nil)
    private let appendRadio = NSButton(radioButtonWithTitle: "Append to current playlist",
                                       target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let importButton = NSButton(title: "Import Selected", target: nil, action: nil)
    private let openSettingsButton = NSButton(title: "Open Settings", target: nil, action: nil)

    // MARK: - Init

    convenience init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        w.title = "Import from Music Library"
        self.init(window: w)
        w.delegate = self
        buildLayout()
        enterLoadingState()
    }

    // MARK: - Public entry

    func beginLoading() {
        Task { @MainActor in
            do {
                let lib = try AppleMusicLibrarySource.loadLibrary()
                self.library = lib
                self.rebuildRows()
                self.enterLoadedState()
            } catch let error as AppleMusicLibraryError {
                self.enterErrorState(error)
            } catch {
                self.enterErrorState(.cannotRead(underlying: error))
            }
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }

        progressIndicator.style = .spinning
        progressIndicator.isIndeterminate = true
        progressIndicator.controlSize = .regular
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 4
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .textBackgroundColor
        tableView.gridStyleMask = []
        let column = NSTableColumn(identifier: .init("row"))
        column.title = ""
        column.width = 440
        column.minWidth = 200
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        newPlaylistRadio.target = self
        newPlaylistRadio.action = #selector(destinationChanged(_:))
        appendRadio.target = self
        appendRadio.action = #selector(destinationChanged(_:))
        appendRadio.state = .on
        newPlaylistRadio.state = .off

        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1B}"

        importButton.target = self
        importButton.action = #selector(importPressed)
        importButton.keyEquivalent = "\r"
        importButton.bezelStyle = .push

        openSettingsButton.target = self
        openSettingsButton.action = #selector(openSettingsPressed)
        openSettingsButton.isHidden = true

        let destStack = NSStackView(views: [appendRadio, newPlaylistRadio])
        destStack.orientation = .vertical
        destStack.alignment = .leading
        destStack.spacing = 4

        let buttonStack = NSStackView(views: [openSettingsButton, NSView(), cancelButton, importButton])
        buttonStack.orientation = .horizontal
        buttonStack.distribution = .fill

        let root = NSStackView(views: [statusLabel, progressIndicator, scrollView, destStack, buttonStack])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.setHuggingPriority(.defaultLow, for: .horizontal)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32),
            scrollView.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32),
            destStack.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32),
            buttonStack.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32),
        ])
    }

    // MARK: - State transitions

    private func enterLoadingState() {
        statusLabel.stringValue = "Reading your Music library…"
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        scrollView.isHidden = true
        newPlaylistRadio.isHidden = true
        appendRadio.isHidden = true
        importButton.isEnabled = false
        openSettingsButton.isHidden = true
    }

    private func enterLoadedState() {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.stringValue = "Select what to import:"
        scrollView.isHidden = false
        newPlaylistRadio.isHidden = false
        appendRadio.isHidden = false
        importButton.isEnabled = true
        openSettingsButton.isHidden = true
        tableView.reloadData()
    }

    private func enterErrorState(_ error: AppleMusicLibraryError) {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        var message = error.localizedDescription
        if let recovery = error.recoverySuggestion {
            message += "\n\n" + recovery
        }
        statusLabel.stringValue = message
        scrollView.isHidden = true
        newPlaylistRadio.isHidden = true
        appendRadio.isHidden = true
        importButton.isEnabled = false
        openSettingsButton.isHidden = !error.canOpenSystemSettings
    }

    // MARK: - Row construction

    private func rebuildRows() {
        guard let lib = library else { rows = []; return }
        var out: [Row] = []
        out.append(.allSongs(count: lib.tracks.count))

        let user = lib.playlists
            .filter { !$0.isBuiltIn && !$0.isSmart }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !user.isEmpty {
            out.append(.sectionHeader("Playlists"))
            for p in user {
                out.append(.playlist(p, count: p.trackIDs.count))
            }
        }
        let smart = lib.playlists
            .filter { !$0.isBuiltIn && $0.isSmart }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !smart.isEmpty {
            out.append(.sectionHeader("Smart Playlists"))
            for p in smart {
                out.append(.playlist(p, count: p.trackIDs.count))
            }
        }
        rows = out
    }

    // MARK: - Actions

    @objc private func cancelPressed() {
        onCancel?()
    }

    @objc private func importPressed() {
        guard let lib = library else { return }
        let picked = collectSelectedTracks(from: lib)
        onImport?(picked, destination)
    }

    @objc private func destinationChanged(_ sender: NSButton) {
        if sender === newPlaylistRadio {
            destination = .newPlaylist
            appendRadio.state = .off
        } else {
            destination = .appendToCurrent
            newPlaylistRadio.state = .off
        }
    }

    @objc private func openSettingsPressed() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc fileprivate func checkboxToggled(_ sender: NSButton) {
        let row = sender.tag
        guard row < rows.count else { return }
        let source: Source
        switch rows[row] {
        case .allSongs: source = .allSongs
        case .playlist(let p, _): source = .playlist(id: p.id)
        case .sectionHeader: return
        }
        if sender.state == .on { selected.insert(source) } else { selected.remove(source) }
        importButton.isEnabled = !selected.isEmpty
    }

    private func collectSelectedTracks(from lib: ITunesLibrary) -> [ITunesTrack] {
        var seen = Set<Int>()
        var out: [ITunesTrack] = []
        func add(_ ids: [Int]) {
            for id in ids where !seen.contains(id) {
                if let t = lib.tracks[id] {
                    out.append(t)
                    seen.insert(id)
                }
            }
        }
        for source in selected {
            switch source {
            case .allSongs:
                add(Array(lib.tracks.keys))
            case .playlist(let id):
                if let p = lib.playlists.first(where: { $0.id == id }) {
                    add(p.trackIDs)
                }
            }
        }
        return out
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onCancel?()
    }
}

// MARK: - Table data/delegate

extension ImportMusicLibraryWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        row < rows.count && rows[row].isCheckable
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 6
        container.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        switch rows[row] {
        case .allSongs(let count):
            let cb = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxToggled(_:)))
            cb.tag = row
            cb.state = selected.contains(.allSongs) ? .on : .off
            let label = NSTextField(labelWithString: "All Songs")
            let count = NSTextField(labelWithString: "\(count) tracks")
            count.textColor = .secondaryLabelColor
            count.font = NSFont.systemFont(ofSize: 11)
            container.addArrangedSubview(cb)
            container.addArrangedSubview(label)
            container.addArrangedSubview(NSView())
            container.addArrangedSubview(count)

        case .sectionHeader(let title):
            let header = NSTextField(labelWithString: title.uppercased())
            header.font = NSFont.boldSystemFont(ofSize: 10)
            header.textColor = .secondaryLabelColor
            container.addArrangedSubview(header)

        case .playlist(let p, let count):
            let cb = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxToggled(_:)))
            cb.tag = row
            cb.state = selected.contains(.playlist(id: p.id)) ? .on : .off
            let label = NSTextField(labelWithString: p.name)
            let sub = NSTextField(labelWithString: "\(count) tracks")
            sub.textColor = .secondaryLabelColor
            sub.font = NSFont.systemFont(ofSize: 11)
            container.addArrangedSubview(cb)
            container.addArrangedSubview(label)
            container.addArrangedSubview(NSView())
            container.addArrangedSubview(sub)
        }

        return container
    }
}
