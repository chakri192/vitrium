import AppKit

/// One tab: a file (or a not-yet-saved buffer) plus the view showing it.
final class Document {

    let id = UUID()
    let pane = EditorPane(frame: .zero)

    private(set) var url: URL?
    private(set) var isDirty = false

    /// What the file's timestamp was the last time we read or wrote it. Used to
    /// tell "someone else changed this on disk" apart from "we just saved it".
    private var knownModificationDate: Date?

    /// Suppresses the reload prompt for a file we already asked about and the
    /// user declined, until it changes again.
    private var ignoredModificationDate: Date?

    var onDirtyChange: (() -> Void)?

    var language: Language = .plain {
        didSet { pane.language = language }
    }

    init(url: URL? = nil) {
        self.url = url
        if let url { self.language = Language.detect(url: url) }
        pane.language = language

        NotificationCenter.default.addObserver(
            self, selector: #selector(textChanged),
            name: NSText.didChangeNotification, object: pane.textView)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: State

    var displayName: String { url?.lastPathComponent ?? "Untitled" }

    var text: String { pane.text }

    var isEmptyUntitled: Bool {
        url == nil && !isDirty && pane.text.isEmpty
    }

    /// Fingerprint of the text as last read from or written to disk.
    ///
    /// Comparing against it means undoing back to the saved state clears the
    /// dirty marker, instead of the tab staying flagged forever after one
    /// keystroke. The length check comes first and is O(1), so the O(n) hash
    /// only runs for edits that leave the length unchanged.
    private var savedLength = 0
    private var savedHash = "".hashValue

    @objc private func textChanged() {
        let nowDirty = pane.textLength != savedLength || pane.text.hashValue != savedHash
        guard nowDirty != isDirty else { return }
        isDirty = nowDirty
        onDirtyChange?()
    }

    private func markClean() {
        savedLength = pane.textLength
        savedHash = pane.text.hashValue
        guard isDirty else { return }
        isDirty = false
        onDirtyChange?()
    }

    // MARK: Loading

    func load(from url: URL, completion: @escaping (Error?) -> Void) {
        FileIO.load(url: url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let loaded):
                // Written straight into this document's own pane — never through
                // "whatever tab is on screen", so several files loading at once
                // cannot splice into each other.
                self.pane.text = loaded.text
                self.url = url
                self.language = Language.detect(url: url)
                self.knownModificationDate = loaded.modificationDate
                self.ignoredModificationDate = nil
                self.markClean()
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }

    // MARK: Saving

    func save(to target: URL? = nil) throws {
        guard let destination = target ?? url else { return }
        knownModificationDate = try FileIO.save(text: pane.text, to: destination)
        ignoredModificationDate = nil
        if url != destination {
            url = destination
            language = Language.detect(url: destination)
        }
        markClean()
    }

    /// The filename the Save dialog should start with, carrying the extension
    /// that matches the tab's detected language so a bare name doesn't save
    /// extensionless.
    var suggestedFileName: String {
        if let url { return url.lastPathComponent }
        return "Untitled.\(language.defaultExtension)"
    }

    // MARK: External changes

    /// True when the file changed on disk since we last touched it and the user
    /// hasn't already dismissed a prompt for that same change.
    func hasUnseenExternalChange() -> Bool {
        guard let url, let known = knownModificationDate else { return false }
        guard let current = FileIO.modificationDate(of: url) else { return false }
        guard current > known else { return false }
        return ignoredModificationDate != current
    }

    func ignoreCurrentExternalChange() {
        guard let url else { return }
        ignoredModificationDate = FileIO.modificationDate(of: url)
    }

    func reloadFromDisk(completion: @escaping (Error?) -> Void) {
        guard let url else { completion(nil); return }
        load(from: url, completion: completion)
    }
}
