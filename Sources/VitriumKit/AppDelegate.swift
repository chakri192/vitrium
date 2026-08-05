import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    private var controller: MainWindowController?
    private var pendingFiles: [URL] = []
    private var didFinishLaunching = false
    private var keyMonitor: Any?

    // MARK: Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Files passed as argv (rather than through the Finder) are collected
        // before the session restore decides what to open.
        pendingFiles += CommandLine.arguments.dropFirst()
            .filter { !$0.hasPrefix("-") }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()

        let controller = MainWindowController()
        self.controller = controller
        controller.restoreSession(openingInstead: pendingFiles)
        pendingFiles = []
        didFinishLaunching = true

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard didFinishLaunching, let controller else {
            pendingFiles += urls
            return
        }
        for url in urls { controller.open(url: url) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard didFinishLaunching else { return }
        controller?.checkForExternalChanges()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        return controller.canTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller?.showWindow(nil) }
        return true
    }

    // MARK: Ctrl+Tab

    /// `⌃⇥` can't be a menu key equivalent — AppKit reserves Tab for view
    /// looping — so it's caught here instead. Physical Control, matching
    /// Safari/Xcode/Terminal, not Command.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let controller = self.controller else { return event }
            guard event.modifierFlags.contains(.control) else { return event }
            guard event.keyCode == 48 else { return event }  // Tab

            if event.modifierFlags.contains(.shift) {
                controller.previousTab(nil)
            } else {
                controller.nextTab(nil)
            }
            return nil
        }
    }

    // MARK: Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(clearRecentFiles) {
            return !Preferences.recentFiles.isEmpty
        }
        return true
    }

    // MARK: Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // Application
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Vitrium", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Vitrium", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Vitrium", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, titled: "Vitrium", to: mainMenu)

        // File
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("New Tab", #selector(MainWindowController.newTab(_:)), "t"))
        fileMenu.addItem(item("Open…", #selector(MainWindowController.openDocument(_:)), "o"))

        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Close Tab", #selector(MainWindowController.closeCurrentTab(_:)), "w"))
        fileMenu.addItem(item("Close Other Tabs", #selector(MainWindowController.closeOtherTabs(_:)), "w", [.command, .option]))
        fileMenu.addItem(item("Close All Tabs", #selector(MainWindowController.closeAllTabs(_:)), "w", [.command, .option, .shift]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Save", #selector(MainWindowController.saveDocument(_:)), "s"))
        fileMenu.addItem(item("Save As…", #selector(MainWindowController.saveDocumentAs(_:)), "s", [.command, .shift]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Reveal in Finder", #selector(MainWindowController.revealInFinder(_:)), "r", [.command, .shift]))
        addSubmenu(fileMenu, titled: "File", to: mainMenu)

        // Edit
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("Undo", Selector(("undo:")), "z"))
        editMenu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        editMenu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Toggle Comment", #selector(MainWindowController.toggleComment(_:)), "/"))
        editMenu.addItem(item("Duplicate Line", #selector(MainWindowController.duplicateLine(_:)), "d"))
        editMenu.addItem(item("Move Line Up", #selector(MainWindowController.moveLineUp(_:)), "\u{F700}", [.option]))
        editMenu.addItem(item("Move Line Down", #selector(MainWindowController.moveLineDown(_:)), "\u{F701}", [.option]))
        editMenu.addItem(item("Shift Right", #selector(MainWindowController.indentSelection(_:)), "]"))
        editMenu.addItem(item("Shift Left", #selector(MainWindowController.outdentSelection(_:)), "["))
        addSubmenu(editMenu, titled: "Edit", to: mainMenu)

        // Find
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(item("Find…", #selector(MainWindowController.showFind(_:)), "f"))
        findMenu.addItem(item("Find and Replace…", #selector(MainWindowController.showFindAndReplace(_:)), "f", [.command, .option]))
        findMenu.addItem(item("Find Next", #selector(MainWindowController.findNext(_:)), "g"))
        findMenu.addItem(item("Find Previous", #selector(MainWindowController.findPrevious(_:)), "g", [.command, .shift]))
        findMenu.addItem(.separator())
        findMenu.addItem(item("Go to Line…", #selector(MainWindowController.goToLine(_:)), "l"))
        addSubmenu(findMenu, titled: "Find", to: mainMenu)

        // View
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(item("Zoom In", #selector(MainWindowController.zoomIn(_:)), "="))
        viewMenu.addItem(item("Zoom Out", #selector(MainWindowController.zoomOut(_:)), "-"))
        viewMenu.addItem(item("Actual Size", #selector(MainWindowController.resetZoom(_:)), "0"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("Toggle Word Wrap", #selector(MainWindowController.toggleWordWrap(_:)), "z", [.option]))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("More Transparent", #selector(MainWindowController.decreaseTint(_:)), "[", [.command, .option]))
        viewMenu.addItem(item("Less Transparent", #selector(MainWindowController.increaseTint(_:)), "]", [.command, .option]))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        addSubmenu(viewMenu, titled: "View", to: mainMenu)

        // Window
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Next Tab", #selector(MainWindowController.nextTab(_:)), "]", [.command, .shift]))
        windowMenu.addItem(item("Previous Tab", #selector(MainWindowController.previousTab(_:)), "[", [.command, .shift]))
        addSubmenu(windowMenu, titled: "Window", to: mainMenu)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func item(_ title: String, _ action: Selector, _ key: String,
                      _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        return menuItem
    }

    private func addSubmenu(_ menu: NSMenu, titled title: String, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        menu.title = title
        mainMenu.addItem(item)
    }

    // MARK: Recent files

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        controller?.open(url: url)
    }

    @objc private func clearRecentFiles() {
        Preferences.clearRecentFiles()
    }
}

extension AppDelegate: NSMenuDelegate {

    /// Rebuilt each time it opens so it reflects saves made since launch.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Open Recent" else { return }
        menu.removeAllItems()

        let recents = Preferences.recentFiles.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        if recents.isEmpty {
            let empty = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for url in recents {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecentFiles), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }
}
