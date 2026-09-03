import AppKit

/// Sheet for entering the Navidrome server, username and password. "Save"
/// pings the server with the typed credentials first, so a bad login is
/// reported inline rather than persisted.
@MainActor
final class NavidromeSettingsWindowController: NSWindowController, NSWindowDelegate {

    /// Called with verified credentials after a successful ping.
    var onSave: ((SubsonicCredentials) -> Void)?
    var onDisconnect: (() -> Void)?
    var onCancel: (() -> Void)?

    private let serverField = NSTextField()
    private let userField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let disconnectButton = NSButton(title: "Disconnect", target: nil, action: nil)
    private let saveButton = NSButton(title: "Connect", target: nil, action: nil)
    private var verifyTask: Task<Void, Never>?

    convenience init(existing: SubsonicCredentials?) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        w.title = "Navidrome Server"
        self.init(window: w)
        w.delegate = self
        buildLayout()
        if let existing {
            serverField.stringValue = existing.serverURL.absoluteString
            userField.stringValue = existing.username
            passwordField.stringValue = existing.password
            disconnectButton.isHidden = false
        } else {
            disconnectButton.isHidden = true
        }
    }

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }

        serverField.placeholderString = "http://192.168.1.10:4533"
        userField.placeholderString = "username"
        passwordField.placeholderString = "password"
        for f in [serverField, userField, passwordField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        }

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Server:"), serverField],
            [NSTextField(labelWithString: "Username:"), userField],
            [NSTextField(labelWithString: "Password:"), passwordField],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.stringValue = "Any Subsonic-compatible server works (Navidrome, Airsonic, Gonic…)."

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true

        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1B}"
        disconnectButton.target = self
        disconnectButton.action = #selector(disconnectPressed)
        saveButton.target = self
        saveButton.action = #selector(savePressed)
        saveButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [disconnectButton, spinner, NSView(), cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.distribution = .fill

        let root = NSStackView(views: [grid, statusLabel, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36),
            statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36),
        ])
    }

    // MARK: - Actions

    @objc private func cancelPressed() {
        verifyTask?.cancel()
        onCancel?()
    }

    @objc private func disconnectPressed() {
        verifyTask?.cancel()
        onDisconnect?()
    }

    @objc private func savePressed() {
        guard let url = NavidromeAccountStore.normalizeServerURL(serverField.stringValue) else {
            showStatus("Enter a server address, e.g. http://192.168.1.10:4533", isError: true)
            return
        }
        let user = userField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty else {
            showStatus("Enter your username.", isError: true)
            return
        }
        let creds = SubsonicCredentials(serverURL: url, username: user, password: passwordField.stringValue)
        setBusy(true)
        showStatus("Connecting to \(creds.displayHost)…", isError: false)
        verifyTask = Task { @MainActor in
            do {
                try await SubsonicClient(credentials: creds).ping()
                guard !Task.isCancelled else { return }
                setBusy(false)
                onSave?(creds)
            } catch {
                guard !Task.isCancelled else { return }
                setBusy(false)
                showStatus(friendly(error), isError: true)
            }
        }
    }

    private func friendly(_ error: Error) -> String {
        if let e = error as? SubsonicError { return e.localizedDescription }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Couldn't reach the server: \(ns.localizedDescription)"
        }
        return ns.localizedDescription
    }

    private func setBusy(_ busy: Bool) {
        spinner.isHidden = !busy
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        saveButton.isEnabled = !busy
        serverField.isEnabled = !busy
        userField.isEnabled = !busy
        passwordField.isEnabled = !busy
    }

    private func showStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    func windowWillClose(_ notification: Notification) {
        verifyTask?.cancel()
        onCancel?()
    }
}
