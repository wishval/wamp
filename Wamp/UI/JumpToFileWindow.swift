import Cocoa

/// Delegate that JumpToFileWindow calls back to. Implemented by AppDelegate.
protocol JumpToFileDelegate: AnyObject {
    /// All tracks in the playlist, in playlist order.
    var jumpCandidates: [JumpFilter.Candidate] { get }
    /// Index of the currently-playing track, or nil.
    var currentTrackIndex: Int? { get }
    /// Play the track at the given playlist index.
    func playTrack(atPlaylistIndex index: Int)
}

final class JumpToFileWindow: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    weak var jumpDelegate: JumpToFileDelegate?

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let goToCurrentButton = NSButton(title: "Go to current", target: nil, action: nil)

    private var matches: [JumpFilter.Match] = []
    private var candidates: [JumpFilter.Candidate] = []

    init() {
        let rect = NSRect(x: 0, y: 0, width: 500, height: 400)
        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Jump to file"
        isFloatingPanel = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        setupContent()
    }

    override var canBecomeKey: Bool { true }

    private func setupContent() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        contentView = content

        // Search field — top
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Type to filter…"
        searchField.delegate = self
        content.addSubview(searchField)

        // Table — single column, no header
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        column.width = 480
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 18
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        if #available(macOS 11.0, *) { tableView.style = .plain }
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .regular

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        content.addSubview(scrollView)

        // Bottom bar
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)

        goToCurrentButton.translatesAutoresizingMaskIntoConstraints = false
        goToCurrentButton.bezelStyle = .rounded
        goToCurrentButton.target = self
        goToCurrentButton.action = #selector(scrollToCurrent)
        content.addSubview(goToCurrentButton)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: goToCurrentButton.centerYAnchor),

            goToCurrentButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            goToCurrentButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
    }

    /// Reset state and present centered over `parent`. Call this every time the user opens the dialog.
    func present(over parent: NSWindow?) {
        candidates = jumpDelegate?.jumpCandidates ?? []
        searchField.stringValue = ""
        recompute()
        if let parent {
            let parentFrame = parent.frame
            let x = parentFrame.midX - frame.width / 2
            let y = parentFrame.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            center()
        }
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)
        // Pre-select current track if visible
        if let curIdx = jumpDelegate?.currentTrackIndex,
           let row = matches.firstIndex(where: { $0.index == curIdx }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
    }

    private func recompute() {
        matches = JumpFilter.filter(query: searchField.stringValue, candidates: candidates)
        tableView.reloadData()
        statusLabel.stringValue = "\(matches.count) of \(candidates.count) tracks"
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        recompute()
        if !matches.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: +1); return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1); return true
        case #selector(NSResponder.moveToBeginningOfDocument(_:)),
             #selector(NSResponder.scrollPageUp(_:)):
            moveSelection(toRow: 0); return true
        case #selector(NSResponder.moveToEndOfDocument(_:)),
             #selector(NSResponder.scrollPageDown(_:)):
            moveSelection(toRow: matches.count - 1); return true
        case #selector(NSResponder.insertNewline(_:)):
            playSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            close(); return true
        case #selector(NSResponder.insertTab(_:)),
             #selector(NSResponder.insertBacktab(_:)):
            // Eat Tab so focus can't escape to the button
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !matches.isEmpty else { return }
        let current = tableView.selectedRow
        let proposed = current < 0 ? (delta > 0 ? 0 : matches.count - 1) : current + delta
        let clamped = max(0, min(matches.count - 1, proposed))
        moveSelection(toRow: clamped)
    }

    private func moveSelection(toRow row: Int) {
        guard row >= 0, row < matches.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    override func keyDown(with event: NSEvent) {
        // Cmd+. is the macOS-native cancel chord.
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "." {
            close()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    func tableView(_ tv: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = tv.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let v = NSTableCellView()
            v.identifier = identifier
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            tf.font = NSFont.systemFont(ofSize: 12)
            v.addSubview(tf)
            v.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            ])
            return v
        }()
        let m = matches[row]
        if let c = candidates.first(where: { $0.index == m.index }) {
            cell.textField?.stringValue = c.displayTitle
        }
        return cell
    }

    // MARK: - Actions

    @objc private func handleDoubleClick() {
        playSelected()
    }

    @objc private func scrollToCurrent() {
        guard let curIdx = jumpDelegate?.currentTrackIndex,
              let row = matches.firstIndex(where: { $0.index == curIdx }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func playSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < matches.count else { return }
        let playlistIndex = matches[row].index
        jumpDelegate?.playTrack(atPlaylistIndex: playlistIndex)
        close()
    }
}
