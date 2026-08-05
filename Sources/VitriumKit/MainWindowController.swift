import AppKit

/// Owns the window, the tab list, and every file operation.
final class MainWindowController: NSWindowController, NSWindowDelegate, FindBarDelegate {

    private let glassWindow: GlassWindow
    private let tabBar = TabBarView()
    private let findBar = FindBarView()
    private let statusBar = StatusBarView()
    private let container = NSView()

    private var documents: [Document] = []
    private var selectedIndex = 0

    private var fontSize = Preferences.fontSize
    private var wrapsLines = Preferences.wrapsLines

    private var findMatches: [NSRange] = []
    private var currentMatch = 0
    private weak var highlightedView: EditorTextView?
    private var highlightedRanges: [NSRange] = []

    private var isCheckingExternalChanges = false

    var currentDocument: Document? {
        documents.indices.contains(selectedIndex) ? documents[selectedIndex] : nil
    }

    // MARK: Setup

    init() {
        let frame = Preferences.windowFrame ?? NSRect(x: 0, y: 0, width: 940, height: 660)
        glassWindow = GlassWindow(contentRect: frame)
        super.init(window: glassWindow)

        glassWindow.delegate = self
        glassWindow.tint = Preferences.tint
        if Preferences.windowFrame == nil { glassWindow.center() }

        buildLayout()
        wireCallbacks()

        NotificationCenter.default.addObserver(
            self, selector: #selector(selectionChanged),
            name: NSTextView.didChangeSelectionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(textChanged),
            name: NSText.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildLayout() {
        guard let content = glassWindow.contentView else { return }

        tabBar.heightAnchor.constraint(equalToConstant: Theme.tabBarHeight).isActive = true
        statusBar.heightAnchor.constraint(equalToConstant: Theme.statusBarHeight).isActive = true
        findBar.isHidden = true

        let stack = NSStackView(views: [tabBar, findBar, container, statusBar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        for view in [tabBar, findBar, container, statusBar] {
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        container.setContentHuggingPriority(.defaultLow, for: .vertical)

        findBar.delegate = self
        // NSWindow forwards the dragging-destination methods to its delegate,
        // so registering here is enough to cover the whole window.
        glassWindow.registerForDraggedTypes([.fileURL])
    }

    private func wireCallbacks() {
        tabBar.onSelect = { [weak self] index in self?.selectTab(index) }
        tabBar.onClose = { [weak self] index in self?.closeTab(at: index) }
        tabBar.onNew = { [weak self] in self?.newTab(nil) }

        statusBar.onSelectLanguage = { [weak self] language in
            guard let self, let document = self.currentDocument else { return }
            document.language = language
            self.refreshChrome()
        }
    }

    /// The Open Recent list, as a popup. A submenu can't carry a useful key
    /// equivalent, so `⌘⇧O` posts the same list here instead.
    @objc func showRecentFiles(_ sender: Any?) {
        let recents = Preferences.recentFiles.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !recents.isEmpty else { NSSound.beep(); return }

        let menu = NSMenu()
        for url in recents {
            let item = NSMenuItem(title: url.lastPathComponent,
                                  action: #selector(openRecentFile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: Theme.trafficLightInset, y: 0), in: tabBar)
    }

    @objc private func openRecentFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open(url: url)
    }

    // MARK: Session

    func restoreSession(openingInstead files: [URL]) {
        if !files.isEmpty {
            for url in files { open(url: url) }
        } else {
            let urls = Preferences.openFiles
                .map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            for url in urls { open(url: url) }
            let restored = Preferences.selectedTab
            if documents.indices.contains(restored) { selectTab(restored) }
        }
        if documents.isEmpty { newTab(nil) }
        refreshChrome()
    }

    private func saveSession() {
        Preferences.openFiles = documents.compactMap { $0.url?.path }
        Preferences.selectedTab = selectedIndex
        Preferences.windowFrame = glassWindow.frame
        Preferences.fontSize = fontSize
        Preferences.wrapsLines = wrapsLines
        Preferences.tint = glassWindow.tint
    }

    // MARK: Tabs

    @discardableResult
    private func addDocument(_ document: Document) -> Document {
        document.pane.fontSize = fontSize
        document.pane.wrapsLines = wrapsLines
        document.onDirtyChange = { [weak self] in self?.refreshChrome() }
        document.pane.textView.onOpenFiles = { [weak self] urls in
            for url in urls { self?.open(url: url) }
        }
        documents.append(document)
        selectTab(documents.count - 1)
        return document
    }

    @objc func newTab(_ sender: Any?) {
        addDocument(Document())
        refreshChrome()
    }

    private func selectTab(_ index: Int) {
        guard documents.indices.contains(index) else { return }
        selectedIndex = index

        container.subviews.forEach { $0.removeFromSuperview() }
        let pane = documents[index].pane
        pane.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pane.topAnchor.constraint(equalTo: container.topAnchor),
            pane.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        pane.focus()

        clearMatchHighlights()
        if !findBar.isHidden {
            recomputeMatches()
            highlightMatches()
            findBar.updateMatchCount(current: findMatches.isEmpty ? 0 : currentMatch + 1,
                                     total: findMatches.count)
        }
        refreshChrome()
    }

    @objc func closeCurrentTab(_ sender: Any?) { closeTab(at: selectedIndex) }

    private func closeTab(at index: Int) {
        guard documents.indices.contains(index) else { return }
        guard confirmClose(of: documents[index]) else { return }

        documents.remove(at: index)
        if documents.isEmpty {
            newTab(nil)
        } else {
            selectTab(min(index, documents.count - 1))
        }
        refreshChrome()
    }

    @objc func closeOtherTabs(_ sender: Any?) {
        guard let keeper = currentDocument else { return }
        for document in documents where document !== keeper {
            guard confirmClose(of: document) else { return }
        }
        documents = [keeper]
        selectTab(0)
        refreshChrome()
    }

    @objc func closeAllTabs(_ sender: Any?) {
        for document in documents {
            guard confirmClose(of: document) else { return }
        }
        documents.removeAll()
        newTab(nil)
        refreshChrome()
    }

    @objc func nextTab(_ sender: Any?) {
        guard !documents.isEmpty else { return }
        selectTab((selectedIndex + 1) % documents.count)
    }

    @objc func previousTab(_ sender: Any?) {
        guard !documents.isEmpty else { return }
        selectTab((selectedIndex - 1 + documents.count) % documents.count)
    }

    /// Blocking Save / Discard / Cancel. Returns false when the user cancels,
    /// which aborts whatever close was in progress.
    private func confirmClose(of document: Document) -> Bool {
        guard document.isDirty else { return true }

        selectTab(documents.firstIndex(where: { $0 === document }) ?? selectedIndex)

        let alert = NSAlert()
        alert.messageText = "Save changes to \(document.displayName)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return performSaveBlocking(document: document)
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: Files

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: glassWindow) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls { self?.open(url: url) }
        }
    }

    func open(url: URL) {
        // Already open? Just go there.
        if let existing = documents.firstIndex(where: { $0.url == url }) {
            selectTab(existing)
            return
        }

        // An untouched empty tab gets reused rather than piling up Untitleds.
        let document: Document
        if let index = documents.firstIndex(where: { $0.isEmptyUntitled }) {
            document = documents[index]
            selectTab(index)
        } else {
            document = addDocument(Document())
        }

        document.load(from: url) { [weak self] error in
            guard let self else { return }
            if let error {
                self.presentError(error, title: "Couldn't open \(url.lastPathComponent)")
                if document.url == nil, let index = self.documents.firstIndex(where: { $0 === document }),
                   self.documents.count > 1 {
                    self.documents.remove(at: index)
                    self.selectTab(min(index, self.documents.count - 1))
                }
            } else {
                Preferences.noteRecentFile(url)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            }
            self.refreshChrome()
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let document = currentDocument else { return }
        performSave(document: document)
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let document = currentDocument else { return }
        performSave(document: document, forcingPanel: true)
    }

    /// Where a save should land, running the panel when the tab has no file yet
    /// or Save As was asked for. Returns nil if the user cancels.
    private func destination(for document: Document, forcingPanel: Bool) -> URL? {
        if let existing = document.url, !forcingPanel { return existing }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.suggestedFileName
        panel.canCreateDirectories = true
        if let existing = document.url {
            panel.directoryURL = existing.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, var url = panel.url else { return nil }

        // A name typed without an extension saves as the tab's language rather
        // than extensionless.
        if url.pathExtension.isEmpty {
            url = url.appendingPathExtension(document.language.defaultExtension)
        }
        return url
    }

    /// The interactive save. The write runs off the main thread, so a large
    /// file doesn't stall typing.
    private func performSave(document: Document, forcingPanel: Bool = false) {
        guard let destination = destination(for: document, forcingPanel: forcingPanel) else { return }

        statusBar.flash("Saving \(destination.lastPathComponent)…", revertingTo: statusPath)
        document.save(to: destination) { [weak self] error in
            guard let self else { return }
            if let error {
                self.presentError(error, title: "Couldn't save \(destination.lastPathComponent)")
            } else {
                self.noteSaved(destination)
                self.statusBar.flash("Saved \(destination.lastPathComponent)", revertingTo: self.statusPath)
            }
            self.refreshChrome()
        }
    }

    /// The blocking save, used only when closing or quitting — the tab can't go
    /// away until the bytes are actually down.
    @discardableResult
    private func performSaveBlocking(document: Document) -> Bool {
        guard let destination = destination(for: document, forcingPanel: false) else { return false }
        do {
            try document.saveSynchronously(to: destination)
            noteSaved(destination)
            refreshChrome()
            return true
        } catch {
            presentError(error, title: "Couldn't save \(destination.lastPathComponent)")
            return false
        }
    }

    private func noteSaved(_ url: URL) {
        Preferences.noteRecentFile(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    @objc func revealInFinder(_ sender: Any?) {
        guard let url = currentDocument?.url else { NSSound.beep(); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: External changes

    /// Checked when the app comes forward rather than by watching file
    /// descriptors — that is when the user can actually act on the answer, and
    /// it can't misfire on our own writes the way a watcher does.
    func checkForExternalChanges() {
        guard !isCheckingExternalChanges else { return }
        isCheckingExternalChanges = true
        defer { isCheckingExternalChanges = false }

        for document in documents where document.hasUnseenExternalChange() {
            selectTab(documents.firstIndex(where: { $0 === document }) ?? selectedIndex)

            let alert = NSAlert()
            alert.messageText = "\(document.displayName) changed on disk."
            alert.informativeText = document.isDirty
                ? "This tab has unsaved changes. Reloading will discard them."
                : "Reload it from disk?"
            alert.addButton(withTitle: "Reload")
            alert.addButton(withTitle: "Keep Mine")
            alert.alertStyle = .informational

            if alert.runModal() == .alertFirstButtonReturn {
                document.reloadFromDisk { [weak self] error in
                    if let error { self?.presentError(error, title: "Couldn't reload") }
                    self?.refreshChrome()
                }
            } else {
                document.ignoreCurrentExternalChange()
            }
        }
    }

    // MARK: Editing commands

    private var textView: EditorTextView? { currentDocument?.pane.textView }

    @objc func toggleComment(_ sender: Any?) { textView?.toggleComment() }
    @objc func duplicateLine(_ sender: Any?) { textView?.duplicateLine() }
    @objc func moveLineUp(_ sender: Any?) { textView?.moveLine(up: true) }
    @objc func moveLineDown(_ sender: Any?) { textView?.moveLine(up: false) }
    @objc func indentSelection(_ sender: Any?) { textView?.indentSelection() }
    @objc func outdentSelection(_ sender: Any?) { textView?.outdentSelection() }

    @objc func goToLine(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "Line number"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn,
              let line = Int(field.stringValue), line > 0 else { return }
        textView?.goToLine(line)
        currentDocument?.pane.focus()
    }

    // MARK: View commands

    @objc func toggleWordWrap(_ sender: Any?) {
        wrapsLines.toggle()
        documents.forEach { $0.pane.wrapsLines = wrapsLines }
        refreshChrome()
    }

    @objc func zoomIn(_ sender: Any?) { setFontSize(fontSize + 1) }
    @objc func zoomOut(_ sender: Any?) { setFontSize(fontSize - 1) }
    @objc func resetZoom(_ sender: Any?) { setFontSize(Theme.defaultFontSize) }

    private func setFontSize(_ size: CGFloat) {
        fontSize = min(Theme.maxFontSize, max(Theme.minFontSize, size))
        documents.forEach { $0.pane.fontSize = fontSize }
        refreshChrome()
    }

    @objc func increaseTint(_ sender: Any?) { adjustTint(by: Theme.tintStep) }
    @objc func decreaseTint(_ sender: Any?) { adjustTint(by: -Theme.tintStep) }

    private func adjustTint(by delta: CGFloat) {
        glassWindow.tint += delta
        statusBar.flash("Glass \(Int((1 - glassWindow.tint / Theme.maxTint) * 100))% transparent",
                        revertingTo: statusPath)
    }

    // MARK: Find

    @objc func showFind(_ sender: Any?) { presentFind(showingReplace: false) }
    @objc func showFindAndReplace(_ sender: Any?) { presentFind(showingReplace: true) }

    private func presentFind(showingReplace: Bool) {
        let selected = textView.map { view -> String in
            let range = view.selectedRange()
            guard range.length > 0, range.length < 200 else { return "" }
            return (view.string as NSString).substring(with: range)
        }
        findBar.present(showingReplace: showingReplace, seed: selected, in: glassWindow)
    }

    @objc func findNext(_ sender: Any?) {
        if findBar.isHidden { presentFind(showingReplace: false); return }
        findBarFindNext(findBar, backwards: false)
    }

    @objc func findPrevious(_ sender: Any?) {
        if findBar.isHidden { presentFind(showingReplace: false); return }
        findBarFindNext(findBar, backwards: true)
    }

    func findBarDidChangeQuery(_ bar: FindBarView) {
        recomputeMatches()
        highlightMatches()
        bar.updateMatchCount(current: findMatches.isEmpty ? 0 : currentMatch + 1,
                             total: findMatches.count)
    }

    func findBarFindNext(_ bar: FindBarView, backwards: Bool) {
        recomputeMatches()
        guard !findMatches.isEmpty, let view = textView else {
            bar.updateMatchCount(current: 0, total: 0)
            NSSound.beep()
            return
        }

        let origin = backwards ? view.selectedRange().location
                               : NSMaxRange(view.selectedRange())
        currentMatch = TextSearcher.nextIndex(in: findMatches, from: origin, backwards: backwards) ?? 0

        let range = findMatches[currentMatch]
        view.setSelectedRange(range)
        view.scrollRangeToVisible(range)
        highlightMatches()
        bar.updateMatchCount(current: currentMatch + 1, total: findMatches.count)
    }

    func findBarReplace(_ bar: FindBarView) {
        guard let view = textView, !bar.query.isEmpty else { return }
        let selection = view.selectedRange()
        let selected = selection.length > 0
            ? (view.string as NSString).substring(with: selection)
            : ""

        let isMatch = bar.matchesCase
            ? selected == bar.query
            : selected.caseInsensitiveCompare(bar.query) == .orderedSame

        if isMatch {
            if view.shouldChangeText(in: selection, replacementString: bar.replacement) {
                view.textStorage?.replaceCharacters(in: selection, with: bar.replacement)
                view.didChangeText()
                view.setSelectedRange(NSRange(location: selection.location + (bar.replacement as NSString).length,
                                              length: 0))
            }
        }
        findBarFindNext(bar, backwards: false)
    }

    func findBarReplaceAll(_ bar: FindBarView) {
        guard let view = textView, !bar.query.isEmpty else { return }
        recomputeMatches()
        guard !findMatches.isEmpty else { NSSound.beep(); return }

        let text = view.string as NSString
        let result = NSMutableString(string: text)
        // Back to front, so earlier ranges stay valid as we go.
        for range in findMatches.reversed() {
            result.replaceCharacters(in: range, with: bar.replacement)
        }

        let whole = NSRange(location: 0, length: text.length)
        // One replaceCharacters call means Replace All is a single undo step.
        guard view.shouldChangeText(in: whole, replacementString: result as String) else { return }
        view.textStorage?.replaceCharacters(in: whole, with: result as String)
        view.didChangeText()
        view.setSelectedRange(NSRange(location: 0, length: 0))

        let count = findMatches.count
        recomputeMatches()
        highlightMatches()
        bar.updateMatchCount(current: 0, total: findMatches.count)
        statusBar.flash("Replaced \(count) occurrence\(count == 1 ? "" : "s")", revertingTo: statusPath)
    }

    /// Reached from the editor's Escape handling via the responder chain.
    @objc func dismissFindBar(_ sender: Any?) {
        guard !findBar.isHidden else { return }
        findBarDidDismiss(findBar)
    }

    func findBarDidDismiss(_ bar: FindBarView) {
        bar.isHidden = true
        clearMatchHighlights()
        findMatches = []
        currentDocument?.pane.focus()
    }

    private func recomputeMatches() {
        guard let view = textView, !findBar.isHidden else { findMatches = []; return }
        findMatches = TextSearcher.matches(of: findBar.query, in: view.string,
                                           matchCase: findBar.matchesCase,
                                           wholeWord: findBar.wholeWord)
        if currentMatch >= findMatches.count { currentMatch = 0 }
    }

    private func highlightMatches() {
        clearMatchHighlights()
        guard let view = textView, let layoutManager = view.layoutManager else { return }
        for (index, range) in findMatches.enumerated() {
            layoutManager.addTemporaryAttributes(
                [.backgroundColor: index == currentMatch ? Theme.findCurrent : Theme.findHighlight],
                forCharacterRange: range)
        }
        highlightedView = view
        highlightedRanges = findMatches
    }

    /// Cleared against the view the highlights were actually applied to, not the
    /// current one — otherwise switching tabs mid-search strands them on the tab
    /// you left. Ranges are tracked individually so this doesn't also wipe the
    /// bracket-match tint.
    private func clearMatchHighlights() {
        guard let view = highlightedView, let layoutManager = view.layoutManager else { return }
        let length = (view.string as NSString).length
        for range in highlightedRanges where NSMaxRange(range) <= length {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
        }
        highlightedRanges = []
        highlightedView = nil
    }

    // MARK: Chrome

    private var statusPath: String {
        guard let document = currentDocument else { return "" }
        guard let url = document.url else { return "Untitled" }
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func refreshChrome() {
        tabBar.items = documents.map { TabBarView.Item(title: $0.displayName, isDirty: $0.isDirty) }
        tabBar.selectedIndex = selectedIndex

        guard let document = currentDocument else { return }
        let position = document.pane.textView.caretPosition
        statusBar.update(path: statusPath, line: position.line, column: position.column,
                         language: document.language, wraps: wrapsLines, fontSize: fontSize)

        glassWindow.title = document.displayName
        glassWindow.representedURL = document.url
        glassWindow.isDocumentEdited = document.isDirty
    }

    @objc private func selectionChanged(_ notification: Notification) {
        guard let view = notification.object as? NSTextView,
              view === textView else { return }
        refreshChrome()
    }

    @objc private func textChanged(_ notification: Notification) {
        guard let view = notification.object as? NSTextView, view === textView else { return }
        refreshChrome()
        if !findBar.isHidden {
            recomputeMatches()
            highlightMatches()
            findBar.updateMatchCount(current: findMatches.isEmpty ? 0 : currentMatch + 1,
                                     total: findMatches.count)
        }
    }

    // MARK: Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard canTerminate() else { return false }
        NSApp.terminate(nil)
        return false
    }

    /// True when every dirty tab has been saved or explicitly discarded.
    func canTerminate() -> Bool {
        for document in documents {
            guard confirmClose(of: document) else { return false }
        }
        saveSession()
        return true
    }

    func windowDidResize(_ notification: Notification) {
        currentDocument?.pane.needsLayout = true
    }

    // MARK: Drag and drop

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURLs(from: sender).isEmpty ? [] : .copy
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(from: sender)
        guard !urls.isEmpty else { return false }
        for url in urls { open(url: url) }
        return true
    }

    private func droppedURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}
