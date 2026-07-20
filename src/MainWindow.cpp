#include "MainWindow.h"
#include "Editor.h"
#include "Highlighter.h"
#include "AutoHideBar.h"
#include "FindBar.h"
#include "TabBar.h"
#include "FileWorker.h"
#include "Theme.h"

#ifndef VITRUM_NO_MAC_VIBRANCY
#include "MacVibrancy.h"
#endif

#include <QVBoxLayout>
#include <QStatusBar>
#include <QLabel>
#include <QFileDialog>
#include <QMessageBox>
#include <QAction>
#include <QMenu>
#include <QKeySequence>
#include <QPainterPath>
#include <QRegion>
#include <QTextCursor>
#include <QTextDocument>
#include <QPlainTextDocumentLayout>
#include <QFileInfo>
#include <QWindow>
#include <QSlider>
#include <QCursor>
#include <QSettings>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QMimeData>
#include <QUrl>
#include <QFileSystemWatcher>
#include <QInputDialog>
#include <QEventLoop>
#include <QtCore/qglobal.h>

namespace {
const char *kAppName = "Vitrum";
}

MainWindow::MainWindow() : QMainWindow(nullptr) {
    setWindowTitle(kAppName);
    resize(980, 680);
    setAcceptDrops(true);

    // Frameless: no native title bar / traffic lights. Dragging + close +
    // minimize come from the hover-reveal AutoHideBar instead.
    setWindowFlag(Qt::FramelessWindowHint, true);
    setAttribute(Qt::WA_TranslucentBackground);
    setStyleSheet("QMainWindow { background: transparent; }");

    auto *container = new QWidget(this);
    auto *layout = new QVBoxLayout(container);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);
    setCentralWidget(container);

    // AutoHideBar is a normal layout item now, not an absolute-positioned
    // overlay -- reveal()/conceal() animate its height, which makes the
    // layout push the tab bar down instead of the two stacking on top of
    // each other (which is what was causing the overlap/ghosting look).
    m_topbar = new AutoHideBar(this);
    layout->addWidget(m_topbar);
    connect(m_topbar, &AutoHideBar::openRequested, this, &MainWindow::openFile);
    connect(m_topbar, &AutoHideBar::saveRequested, this, &MainWindow::saveFile);
    connect(m_topbar, &AutoHideBar::saveAsRequested, this, &MainWindow::saveFileAs);
    connect(m_topbar, &AutoHideBar::closeRequested, this, &QWidget::close);
    connect(m_topbar, &AutoHideBar::minimizeRequested, this, &QWidget::showMinimized);
    connect(m_topbar, &AutoHideBar::maximizeRequested, this, &MainWindow::toggleMaximized);
    connect(m_topbar->opacitySlider(), &QSlider::valueChanged, this, &MainWindow::setGlassOpacity);

    m_tabBar = new TabBar(container);
    layout->addWidget(m_tabBar);
    connect(m_tabBar, &TabBar::tabActivated, this, &MainWindow::activateTab);
    connect(m_tabBar, &TabBar::tabCloseRequested, this, &MainWindow::requestCloseTab);
    connect(m_tabBar, &TabBar::newTabRequested, this, &MainWindow::newTab);

    m_editor = new Editor(container);
    layout->addWidget(m_editor);

    connect(m_editor, &Editor::opacityChanged, this, &MainWindow::onOpacityChanged);
    connect(m_editor, &QPlainTextEdit::textChanged, this, &MainWindow::markDirty);
    connect(m_editor, &QPlainTextEdit::cursorPositionChanged, this, &MainWindow::updatePositionLabel);

    m_findBar = new FindBar(m_editor, this);

    m_barHideTimer.setSingleShot(true);
    connect(&m_barHideTimer, &QTimer::timeout, this, &MainWindow::concealBar);

    // Cursor-position polling instead of relying on mouseMoveEvent/enterEvent/
    // leaveEvent -- Qt's hover-event delivery doesn't reliably handle a
    // widget whose visibility changes at runtime.
    connect(&m_hoverPollTimer, &QTimer::timeout, this, &MainWindow::pollHover);
    m_hoverPollTimer.start(Theme::kHoverPollMs);

    buildActions();
    buildStatusBar();

    m_fsWatcher = new QFileSystemWatcher(this);
    connect(m_fsWatcher, &QFileSystemWatcher::fileChanged, this, &MainWindow::onFileChangedOnDisk);

    const int firstTab = createTab();
    switchToTab(firstTab);

    loadSettings();
}

MainWindow::~MainWindow() {
    // A QThread must never be destroyed while still running. Both workers
    // are normally short-lived (deleteLater on QThread::finished), but if
    // the window is torn down while a load/save is still in flight, force
    // it to stop and join here rather than risking a crash.
    if (m_loadWorker) {
        m_loadWorker->abort();
        m_loadWorker->wait();
    }
    if (m_saveWorker) {
        m_saveWorker->wait();
    }
}

// --------------------------------------------------------------- tabs -----

int MainWindow::createTab(const QString &path) {
    DocumentTab tab;
    tab.path = path;
    tab.document = new QTextDocument(this);
    // QTextDocument defaults to the rich-text layout engine; QPlainTextEdit
    // requires QPlainTextDocumentLayout specifically (its own auto-created
    // default document already has this set, but a manually-created one
    // does not, and setDocument() silently rejects the mismatch).
    tab.document->setDocumentLayout(new QPlainTextDocumentLayout(tab.document));
    tab.highlighter = new Highlighter(tab.document);
    if (!path.isEmpty()) tab.highlighter->setLanguageForPath(path);

    const QString label = path.isEmpty() ? "untitled" : QFileInfo(path).fileName();
    const int index = m_tabBar->addTab(label);
    m_tabs.append(tab);
    return index;
}

void MainWindow::switchToTab(int index) {
    if (index < 0 || index >= m_tabs.size()) return;

    if (m_activeTab >= 0 && m_activeTab < m_tabs.size())
        m_tabs[m_activeTab].savedCursorPos = m_editor->textCursor().position();

    m_activeTab = index;
    DocumentTab &tab = m_tabs[index];

    // adoptDocument() re-applies line-height/base-text-color formatting via
    // QTextCursor merges, which legitimately fire textChanged even though no
    // real user edit happened -- that was flipping every freshly-switched-to
    // tab's dirty flag to true (breaking tab reuse, and worse: causing
    // closeTabAt's "unsaved changes?" dialog to pop for tabs that were never
    // actually dirty). Capture the true state first, restore it after.
    const bool dirtyBefore = tab.dirty;
    m_editor->adoptDocument(tab.document);
    tab.dirty = dirtyBefore;
    m_tabBar->setTabDirty(index, dirtyBefore);

    QTextCursor c(tab.document);
    c.setPosition(qMin(tab.savedCursorPos, qMax(0, tab.document->characterCount() - 1)));
    m_editor->setTextCursor(c);

    m_tabBar->setActiveTab(index);
    m_editor->setReadOnly(tab.loading);
    m_langLabel->setText(tab.highlighter->language());
    m_fileLabel->setText(tab.loading
        ? QString("loading %1...").arg(QFileInfo(tab.path.isEmpty() ? m_currentLoadPath : tab.path).fileName())
        : (tab.path.isEmpty() ? "untitled" : tab.path));
    setWindowTitle(QString("%1 \u2014 %2%3").arg(kAppName,
        tab.path.isEmpty() ? "untitled" : QFileInfo(tab.path).fileName(),
        tab.dirty ? " \u25CF" : ""));
    updatePositionLabel();
    m_editor->setFocus();
}

void MainWindow::activateTab(int index) { switchToTab(index); }

void MainWindow::closeTabAt(int index) {
    if (index < 0 || index >= m_tabs.size()) return;
    DocumentTab &tab = m_tabs[index];

    if (tab.loading) return;  // don't yank the document out from under an in-flight load

    if (tab.dirty && !confirmDiscardOrSave(index, "closing")) return;

    const bool wasActive = (index == m_activeTab);
    if (!tab.path.isEmpty()) unwatchPath(tab.path);
    tab.document->deleteLater();  // highlighter is parented to the document
    m_tabs.removeAt(index);
    m_tabBar->removeTab(index);

    if (m_tabs.isEmpty()) {
        const int fresh = createTab();
        m_activeTab = -1;
        switchToTab(fresh);
        return;
    }

    if (wasActive) {
        m_activeTab = -1;
        switchToTab(qMin(index, m_tabs.size() - 1));
    } else if (index < m_activeTab) {
        --m_activeTab;
    }
}

// Shows a Save / Discard / Cancel prompt for a dirty tab. Returns true if
// it's now safe to proceed with whatever the caller wanted to do (close the
// tab, close the window); false means the user cancelled.
bool MainWindow::confirmDiscardOrSave(int index, const QString &verb) {
    if (index < 0 || index >= m_tabs.size()) return true;
    DocumentTab &tab = m_tabs[index];
    if (m_activeTab != index) switchToTab(index);

    QMessageBox box(this);
    box.setIcon(QMessageBox::Warning);
    box.setWindowTitle("Unsaved Changes");
    box.setText(QString("Save changes to %1 before %2?")
        .arg(tab.path.isEmpty() ? "untitled" : QFileInfo(tab.path).fileName(), verb));
    box.setStandardButtons(QMessageBox::Save | QMessageBox::Discard | QMessageBox::Cancel);
    box.setDefaultButton(QMessageBox::Save);
    const int resp = box.exec();

    if (resp == QMessageBox::Cancel) return false;
    if (resp == QMessageBox::Save) return saveTabAndWait(index);
    return true;  // Discard
}

// Saves a specific tab and blocks (via a nested event loop, so the UI stays
// responsive) until it either completes or fails. Used by confirmation
// dialogs, where the surrounding close/quit action can't proceed until the
// save has actually finished.
bool MainWindow::saveTabAndWait(int index) {
    if (index < 0 || index >= m_tabs.size()) return false;
    DocumentTab &tab = m_tabs[index];

    QString path = tab.path;
    if (path.isEmpty()) {
        path = QFileDialog::getSaveFileName(this, "Save File");
        if (path.isEmpty()) return false;
    }

    const QString text = (index == m_activeTab) ? m_editor->toPlainText() : tab.document->toPlainText();

    FileSaveWorker worker(path, text);
    QEventLoop loop;
    bool ok = false;
    QString errorMessage;
    connect(&worker, &FileSaveWorker::finishedSaving, &loop, [&] { ok = true; loop.quit(); });
    connect(&worker, &FileSaveWorker::failed, &loop, [&](const QString &msg) { errorMessage = msg; loop.quit(); });
    worker.start();
    loop.exec();
    worker.wait();

    if (!ok) {
        QMessageBox::critical(this, "Save File Failed", errorMessage);
        return false;
    }

    if (!tab.path.isEmpty() && tab.path != path) unwatchPath(tab.path);
    tab.path = path;
    tab.dirty = false;
    m_tabBar->setTabDirty(index, false);
    tab.highlighter->setLanguageForPath(path);
    refreshTabLabel(index);
    addToRecentFiles(path);
    m_selfWritePaths.insert(path);
    watchPath(path);

    if (index == m_activeTab) {
        m_langLabel->setText(tab.highlighter->language());
        m_fileLabel->setText(path);
        setWindowTitle(QString("%1 \u2014 %2").arg(kAppName, QFileInfo(path).fileName()));
    }
    return true;
}

void MainWindow::requestCloseTab(int index) { closeTabAt(index); }

void MainWindow::newTab() { switchToTab(createTab()); }
void MainWindow::closeCurrentTab() { closeTabAt(m_activeTab); }

void MainWindow::nextTab() {
    if (m_tabs.isEmpty()) return;
    switchToTab((m_activeTab + 1) % m_tabs.size());
}

void MainWindow::previousTab() {
    if (m_tabs.isEmpty()) return;
    switchToTab((m_activeTab - 1 + m_tabs.size()) % m_tabs.size());
}

void MainWindow::refreshTabLabel(int index) {
    if (index < 0 || index >= m_tabs.size()) return;
    const QString &path = m_tabs[index].path;
    m_tabBar->setTabLabel(index, path.isEmpty() ? "untitled" : QFileInfo(path).fileName());
}

MainWindow::DocumentTab &MainWindow::currentTab() {
    static DocumentTab dummy;
    if (m_activeTab < 0 || m_activeTab >= m_tabs.size()) return dummy;
    return m_tabs[m_activeTab];
}

// ------------------------------------------------------------- glass ------

void MainWindow::showEvent(QShowEvent *event) {
    QMainWindow::showEvent(event);
#ifndef VITRUM_NO_MAC_VIBRANCY
    if (!m_effectView && qEnvironmentVariableIsSet("VITRUM_ENABLE_GLASS")) {
        if (QWindow *handle = windowHandle()) {
            m_effectView = MacVibrancy::installGlass(handle, Theme::kWindowRadius, "hud");
            if (m_effectView) MacVibrancy::setGlassAlpha(m_effectView, 1.0);
        }
    }
#endif
}

void MainWindow::resizeEvent(QResizeEvent *event) {
    QMainWindow::resizeEvent(event);
    repositionFindBar();
    applyRoundedMask();
}

void MainWindow::repositionFindBar() {
    if (!m_findBar) return;
    const QSize hint = m_findBar->sizeHint();
    const int top = m_topbar->height() + m_tabBar->height() + 8;
    m_findBar->setGeometry(width() - hint.width() - 16, top, hint.width(), hint.height());
}

void MainWindow::applyRoundedMask() {
    QPainterPath path;
    path.addRoundedRect(QRectF(rect()), Theme::kWindowRadius, Theme::kWindowRadius);
    setMask(QRegion(path.toFillPolygon().toPolygon()));
}

void MainWindow::setGlassOpacity(int alpha) {
    m_editor->setBackgroundAlpha(alpha);
}

void MainWindow::onOpacityChanged(int alpha) {
    auto *slider = m_topbar->opacitySlider();
    if (slider->value() != alpha) {
        slider->blockSignals(true);
        slider->setValue(alpha);
        slider->blockSignals(false);
    }
}

void MainWindow::pollHover() {
    const QPoint local = mapFromGlobal(QCursor::pos());
    const bool insideWindow = rect().contains(local);
    const bool inRevealZone = insideWindow && local.y() <= Theme::kRevealZonePx;
    const bool inBarArea =
        insideWindow && m_topbar->isRevealed() && local.y() >= 0 && local.y() <= Theme::kBarHeight;

    if (inRevealZone || inBarArea) {
        cancelBarHide();
        if (!m_topbar->isRevealed()) m_topbar->reveal();
    } else if (m_topbar->isRevealed() && !m_barHideTimer.isActive()) {
        scheduleBarHide();
    }
    repositionFindBar();
}

void MainWindow::cancelBarHide() { m_barHideTimer.stop(); }
void MainWindow::scheduleBarHide() { m_barHideTimer.start(Theme::kHideDelayMs); }
void MainWindow::concealBar() { m_topbar->conceal(); }

void MainWindow::toggleMaximized() {
    if (isMaximized())
        showNormal();
    else
        showMaximized();
}

void MainWindow::goToLine() {
    const int maxLine = qMax(1, m_editor->document()->blockCount());
    const int currentLine = m_editor->textCursor().blockNumber() + 1;
    bool ok = false;
    const int line = QInputDialog::getInt(this, "Go to Line",
        QString("Line number (1\u2013%1):").arg(maxLine), currentLine, 1, maxLine, 1, &ok);
    if (!ok) return;

    QTextCursor cursor(m_editor->document()->findBlockByNumber(line - 1));
    m_editor->setTextCursor(cursor);
    m_editor->centerCursor();
    m_editor->setFocus();
}

void MainWindow::toggleWordWrap() {
    m_wordWrap = !m_wordWrap;
    m_editor->setLineWrapMode(m_wordWrap ? QPlainTextEdit::WidgetWidth : QPlainTextEdit::NoWrap);
}

// --------------------------------------------------------- drag and drop --

void MainWindow::dragEnterEvent(QDragEnterEvent *event) {
    if (event->mimeData()->hasUrls()) event->acceptProposedAction();
}

void MainWindow::dropEvent(QDropEvent *event) {
    for (const QUrl &url : event->mimeData()->urls())
        if (url.isLocalFile()) loadFile(url.toLocalFile());
}

// ------------------------------------------------------------- actions ----

void MainWindow::buildActions() {
    auto addAct = [&](const QString &label, QKeySequence shortcut, auto slot) {
        auto *act = new QAction(label, this);
        act->setShortcut(shortcut);
        connect(act, &QAction::triggered, this, slot);
        addAction(act);
    };
    addAct("Open", QKeySequence::Open, &MainWindow::openFile);
    addAct("Save", QKeySequence::Save, &MainWindow::saveFile);
    addAct("Save As", QKeySequence::SaveAs, &MainWindow::saveFileAs);
    addAct("New Tab", QKeySequence("Ctrl+T"), &MainWindow::newTab);
    addAct("Close Tab", QKeySequence("Ctrl+W"), &MainWindow::closeCurrentTab);
    addAct("Next Tab", QKeySequence("Ctrl+Shift+]"), &MainWindow::nextTab);
    addAct("Previous Tab", QKeySequence("Ctrl+Shift+["), &MainWindow::previousTab);
    addAct("Go to Line", QKeySequence("Ctrl+G"), &MainWindow::goToLine);
    addAct("Toggle Word Wrap", QKeySequence("Alt+Z"), &MainWindow::toggleWordWrap);
    addAct("Quit", QKeySequence::Quit, &QWidget::close);

    // Glass opacity lives on bracket keys -- Ctrl+=/Ctrl+- are freed up for
    // the far more standard "zoom text size" convention below instead.
    auto *incAct = new QAction("Increase Glass Opacity", this);
    incAct->setShortcut(QKeySequence("]"));
    connect(incAct, &QAction::triggered, this,
            [this] { setGlassOpacity(m_editor->backgroundAlpha() + 15); });
    addAction(incAct);

    auto *decAct = new QAction("Decrease Glass Opacity", this);
    decAct->setShortcut(QKeySequence("["));
    connect(decAct, &QAction::triggered, this,
            [this] { setGlassOpacity(m_editor->backgroundAlpha() - 15); });
    addAction(decAct);

    auto *zoomInAct = new QAction("Zoom In", this);
    zoomInAct->setShortcut(QKeySequence::ZoomIn);
    connect(zoomInAct, &QAction::triggered, m_editor, &Editor::zoomTextIn);
    addAction(zoomInAct);

    auto *zoomOutAct = new QAction("Zoom Out", this);
    zoomOutAct->setShortcut(QKeySequence::ZoomOut);
    connect(zoomOutAct, &QAction::triggered, m_editor, &Editor::zoomTextOut);
    addAction(zoomOutAct);

    auto *zoomResetAct = new QAction("Reset Zoom", this);
    zoomResetAct->setShortcut(QKeySequence("Ctrl+0"));
    connect(zoomResetAct, &QAction::triggered, m_editor, &Editor::resetTextZoom);
    addAction(zoomResetAct);

    auto *findAct = new QAction("Find", this);
    findAct->setShortcut(QKeySequence::Find);
    connect(findAct, &QAction::triggered, m_findBar, &FindBar::openFind);
    addAction(findAct);

    auto *replaceAct = new QAction("Find and Replace", this);
    replaceAct->setShortcut(QKeySequence::Replace);
    connect(replaceAct, &QAction::triggered, m_findBar, &FindBar::openReplace);
    addAction(replaceAct);

    auto *findNextAct = new QAction("Find Next", this);
    findNextAct->setShortcut(QKeySequence::FindNext);
    connect(findNextAct, &QAction::triggered, this, [this] { m_findBar->openFind(); });
    addAction(findNextAct);

    auto *recentAct = new QAction("Open Recent", this);
    recentAct->setShortcut(QKeySequence("Ctrl+Shift+O"));
    connect(recentAct, &QAction::triggered, this, [this] {
        if (m_recentFiles.isEmpty()) return;
        QMenu menu(this);
        for (const QString &path : m_recentFiles) {
            QAction *item = menu.addAction(QFileInfo(path).fileName());
            connect(item, &QAction::triggered, this, [this, path] { loadFile(path); });
        }
        menu.exec(QCursor::pos());
    });
    addAction(recentAct);
}

void MainWindow::buildStatusBar() {
    auto *sb = new QStatusBar(this);
    sb->setStyleSheet(QString(
        "QStatusBar { background: rgba(7, 9, 9, 235); color: #6E8A79; "
        "border-top: 1px solid rgba(%1, %2, %3, 40); font-size: 11px; }")
        .arg(kAccent.red()).arg(kAccent.green()).arg(kAccent.blue()));
    sb->setToolTip(QStringLiteral(
        "\u2318O open   \u2318S save   \u2318T new tab   \u2318W close tab   "
        "\u2318F find   \u2318G go to line   \u2325Z word wrap   "
        "[ ] glass opacity   \u2318+/- zoom   \u2318\u21e7O recent"));
    setStatusBar(sb);
    m_posLabel = new QLabel("Ln 1, Col 1", this);
    m_langLabel = new QLabel("plain", this);
    m_fileLabel = new QLabel("untitled", this);
    sb->addPermanentWidget(m_posLabel);
    sb->addPermanentWidget(m_langLabel);
    sb->addWidget(m_fileLabel);
}

void MainWindow::updatePositionLabel() {
    const QTextCursor cursor = m_editor->textCursor();
    m_posLabel->setText(QString("Ln %1, Col %2")
        .arg(cursor.blockNumber() + 1)
        .arg(cursor.positionInBlock() + 1));
}

void MainWindow::markDirty() {
    if (m_activeTab < 0) return;
    currentTab().dirty = true;
    m_tabBar->setTabDirty(m_activeTab, true);
    const QString title = currentTab().path.isEmpty()
        ? "untitled" : QFileInfo(currentTab().path).fileName();
    setWindowTitle(QString("%1 \u2014 %2 \u25CF").arg(kAppName, title));
}

// --------------------------------------------------------- file operations

void MainWindow::openFile() {
    const QString path = QFileDialog::getOpenFileName(this, "Open File");
    if (path.isEmpty()) return;
    loadFile(path);
}

int MainWindow::findTabForPath(const QString &path) const {
    const QFileInfo target(path);
    const QString targetKey = target.exists() ? target.canonicalFilePath() : target.absoluteFilePath();
    for (int i = 0; i < m_tabs.size(); ++i) {
        const QString &tabPath = m_tabs[i].path;
        if (tabPath.isEmpty()) continue;
        const QFileInfo tabInfo(tabPath);
        const QString tabKey = tabInfo.exists() ? tabInfo.canonicalFilePath() : tabInfo.absoluteFilePath();
        if (tabKey == targetKey) return i;
    }
    return -1;
}

void MainWindow::loadFile(const QString &path) {
    const int existing = findTabForPath(path);
    if (existing >= 0 && !m_tabs[existing].loading) {
        switchToTab(existing);
        return;
    }

    m_loadQueue.enqueue({path, -1});
    if (!m_loadWorker) startNextLoad();
}

void MainWindow::startNextLoad() {
    if (m_loadQueue.isEmpty()) return;
    const QueuedLoad q = m_loadQueue.dequeue();

    int tabIndex = q.tabIndex;
    if (tabIndex < 0) {
        // Decide reuse-vs-new-tab *now*, using the true current state --
        // deciding this back when loadFile() was first called (as the
        // original code did) breaks as soon as more than one load is
        // queued, since the earlier loads haven't landed yet.
        const bool reuse = m_activeTab >= 0 && m_tabs[m_activeTab].path.isEmpty() &&
                            !m_tabs[m_activeTab].dirty && !m_tabs[m_activeTab].loading &&
                            m_tabs[m_activeTab].document->isEmpty();
        m_currentLoadCreatedTab = !reuse;
        tabIndex = reuse ? m_activeTab : createTab();
    } else {
        m_currentLoadCreatedTab = false;
    }

    switchToTab(tabIndex);
    m_currentLoadTabIndex = tabIndex;
    m_currentLoadPath = q.path;

    DocumentTab &tab = m_tabs[tabIndex];
    tab.loading = true;
    tab.document->clear();
    m_editor->setReadOnly(true);
    m_fileLabel->setText(QString("loading %1...").arg(QFileInfo(q.path).fileName()));

    m_loadWorker = new FileLoadWorker(q.path, this);
    connect(m_loadWorker, &FileLoadWorker::chunkReady, this, &MainWindow::appendChunk);
    connect(m_loadWorker, &FileLoadWorker::finishedLoading, this, &MainWindow::finishLoad);
    connect(m_loadWorker, &FileLoadWorker::failed, this, &MainWindow::loadFailed);
    connect(m_loadWorker, &QThread::finished, m_loadWorker, &QObject::deleteLater);
    m_loadWorker->start();
}

void MainWindow::appendChunk(const QString &chunk) {
    if (m_currentLoadTabIndex < 0 || m_currentLoadTabIndex >= m_tabs.size()) return;
    // Written straight into the loading tab's own document, never through
    // m_editor -- if the user switches tabs mid-load, m_editor now shows a
    // *different* document, and appending through it would splice this
    // file's contents into whatever tab happens to be visible.
    QTextCursor cursor(m_tabs[m_currentLoadTabIndex].document);
    cursor.movePosition(QTextCursor::End);
    cursor.insertText(chunk);
}

void MainWindow::finishLoad() {
    m_loadWorker = nullptr;
    if (m_currentLoadTabIndex < 0 || m_currentLoadTabIndex >= m_tabs.size()) { startNextLoad(); return; }

    const int index = m_currentLoadTabIndex;
    DocumentTab &tab = m_tabs[index];
    tab.loading = false;
    tab.path = m_currentLoadPath;
    tab.dirty = false;
    tab.highlighter->setLanguageForPath(m_currentLoadPath);
    refreshTabLabel(index);
    m_tabBar->setTabDirty(index, false);
    addToRecentFiles(m_currentLoadPath);
    watchPath(m_currentLoadPath);

    if (index == m_activeTab) {
        m_editor->setReadOnly(false);
        m_editor->ensureTextVisible();
        m_langLabel->setText(tab.highlighter->language());
        m_fileLabel->setText(tab.path);
        setWindowTitle(QString("%1 \u2014 %2").arg(kAppName, QFileInfo(tab.path).fileName()));
    }

    startNextLoad();
}

void MainWindow::loadFailed(const QString &message) {
    m_loadWorker = nullptr;
    if (m_currentLoadTabIndex >= 0 && m_currentLoadTabIndex < m_tabs.size()) {
        DocumentTab &tab = m_tabs[m_currentLoadTabIndex];
        tab.loading = false;
        if (m_currentLoadTabIndex == m_activeTab) {
            m_editor->setReadOnly(false);
            m_fileLabel->setText(tab.path.isEmpty() ? "untitled" : tab.path);
        }
        // A tab created purely to hold this failed load would otherwise
        // sit around as a dead "untitled" tab the user never asked for.
        if (m_currentLoadCreatedTab && m_tabs.size() > 1)
            closeTabAt(m_currentLoadTabIndex);
    }
    QMessageBox::critical(this, "Open File Failed", message);
    startNextLoad();
}

void MainWindow::saveFile() {
    if (currentTab().path.isEmpty()) {
        saveFileAs();
        return;
    }
    saveTo(currentTab().path);
}

void MainWindow::saveFileAs() {
    const QString path = QFileDialog::getSaveFileName(this, "Save File");
    if (path.isEmpty()) return;
    saveTo(path);
}

void MainWindow::saveTo(const QString &path) {
    if (m_saveWorker) {
        // A save is already running (e.g. user mashed Ctrl+S) -- let it
        // finish rather than racing two writers against the same file.
        return;
    }
    m_saveWorker = new FileSaveWorker(path, m_editor->toPlainText(), this);
    connect(m_saveWorker, &FileSaveWorker::finishedSaving, this,
            [this, path] { m_saveWorker = nullptr; finishSave(path); });
    connect(m_saveWorker, &FileSaveWorker::failed, this, [this](const QString &msg) {
        m_saveWorker = nullptr;
        QMessageBox::critical(this, "Save File Failed", msg);
    });
    connect(m_saveWorker, &QThread::finished, m_saveWorker, &QObject::deleteLater);
    m_saveWorker->start();
}

void MainWindow::finishSave(const QString &path) {
    if (!currentTab().path.isEmpty() && currentTab().path != path) unwatchPath(currentTab().path);
    currentTab().path = path;
    currentTab().dirty = false;
    m_tabBar->setTabDirty(m_activeTab, false);
    currentTab().highlighter->setLanguageForPath(path);
    m_langLabel->setText(currentTab().highlighter->language());
    m_fileLabel->setText(path);
    setWindowTitle(QString("%1 \u2014 %2").arg(kAppName, QFileInfo(path).fileName()));
    refreshTabLabel(m_activeTab);
    addToRecentFiles(path);
    m_selfWritePaths.insert(path);
    watchPath(path);
}

// ------------------------------------------------------ external changes --

void MainWindow::watchPath(const QString &path) {
    if (path.isEmpty() || !m_fsWatcher) return;
    if (!m_fsWatcher->files().contains(path)) m_fsWatcher->addPath(path);
}

void MainWindow::unwatchPath(const QString &path) {
    if (path.isEmpty() || !m_fsWatcher) return;
    m_fsWatcher->removePath(path);
    m_selfWritePaths.remove(path);
}

void MainWindow::onFileChangedOnDisk(const QString &path) {
    // A save we just performed ourselves also fires this signal (the
    // underlying inode changes on the atomic rename QSaveFile does) --
    // that's not an external edit, so swallow exactly one notification per
    // save rather than asking "reload?" about our own write.
    if (m_selfWritePaths.remove(path)) return;

    const int index = findTabForPath(path);
    if (index < 0) return;

    // Editors like this commonly lose the OS-level watch after an atomic
    // replace (the watched inode is gone). Re-arm it if the file still
    // exists so future external edits keep being caught.
    if (QFileInfo::exists(path)) watchPath(path);

    DocumentTab &tab = m_tabs[index];
    if (tab.loading) return;

    if (tab.dirty) {
        // Don't clobber unsaved local edits with a surprise reload -- just
        // let the user know, non-intrusively, next time they look at it.
        if (index == m_activeTab) m_fileLabel->setText(tab.path + "  (modified on disk)");
        return;
    }

    if (m_activeTab != index) switchToTab(index);
    const auto resp = QMessageBox::question(this, "File Changed on Disk",
        QString("%1 was changed by another program. Reload it?").arg(QFileInfo(path).fileName()),
        QMessageBox::Yes | QMessageBox::No);
    if (resp == QMessageBox::Yes) reloadTab(index);
}

void MainWindow::reloadTab(int index) {
    if (index < 0 || index >= m_tabs.size() || m_tabs[index].loading) return;
    m_loadQueue.enqueue({m_tabs[index].path, index});
    if (!m_loadWorker) startNextLoad();
}

// -------------------------------------------------------------- settings --

void MainWindow::addToRecentFiles(const QString &path) {
    m_recentFiles.removeAll(path);
    m_recentFiles.prepend(path);
    while (m_recentFiles.size() > Theme::kMaxRecentFiles) m_recentFiles.removeLast();
}

void MainWindow::loadSettings() {
    QSettings settings;
    if (settings.contains("geometry")) restoreGeometry(settings.value("geometry").toByteArray());
    m_recentFiles = settings.value("recentFiles").toStringList();
    setGlassOpacity(settings.value("glassAlpha", Theme::kDefaultAlpha).toInt());

    m_wordWrap = settings.value("wordWrap", false).toBool();
    m_editor->setLineWrapMode(m_wordWrap ? QPlainTextEdit::WidgetWidth : QPlainTextEdit::NoWrap);

    // Reopen whatever was on-screen last time. Missing/deleted files are
    // silently skipped rather than surfacing an error dialog on every
    // startup for a file the user may have intentionally removed.
    const QStringList sessionFiles = settings.value("sessionFiles").toStringList();
    for (const QString &path : sessionFiles) {
        if (QFileInfo::exists(path)) loadFile(path);
    }
}

void MainWindow::saveSettings() {
    QSettings settings;
    settings.setValue("geometry", saveGeometry());
    settings.setValue("recentFiles", m_recentFiles);
    settings.setValue("glassAlpha", m_editor->backgroundAlpha());
    settings.setValue("wordWrap", m_wordWrap);

    QStringList sessionFiles;
    for (const auto &tab : m_tabs)
        if (!tab.path.isEmpty()) sessionFiles.append(tab.path);
    settings.setValue("sessionFiles", sessionFiles);
}

void MainWindow::closeEvent(QCloseEvent *event) {
    if (m_currentLoadTabIndex >= 0 && m_loadWorker) {
        const auto resp = QMessageBox::question(this, "File Still Loading",
            "A file is still being opened. Quit anyway and cancel the load?",
            QMessageBox::Yes | QMessageBox::No);
        if (resp != QMessageBox::Yes) { event->ignore(); return; }
    }

    for (int i = 0; i < m_tabs.size(); ++i) {
        if (!m_tabs[i].dirty) continue;
        if (!confirmDiscardOrSave(i, "quitting")) {
            event->ignore();
            return;
        }
    }

    saveSettings();
    event->accept();
}
