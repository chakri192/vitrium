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

    m_topbar = new AutoHideBar(this);
    connect(m_topbar, &AutoHideBar::openRequested, this, &MainWindow::openFile);
    connect(m_topbar, &AutoHideBar::saveRequested, this, &MainWindow::saveFile);
    connect(m_topbar, &AutoHideBar::saveAsRequested, this, &MainWindow::saveFileAs);
    connect(m_topbar, &AutoHideBar::closeRequested, this, &QWidget::close);
    connect(m_topbar, &AutoHideBar::minimizeRequested, this, &QWidget::showMinimized);
    connect(m_topbar, &AutoHideBar::maximizeRequested, this, &MainWindow::toggleMaximized);
    connect(m_topbar->opacitySlider(), &QSlider::valueChanged, this, &MainWindow::setGlassOpacity);

    // Cursor-position polling instead of relying on mouseMoveEvent/enterEvent/
    // leaveEvent across a widget (the bar) that gets raised and re-stacked at
    // runtime -- that event-delivery chain is exactly the kind of thing Qt's
    // hover tracking doesn't handle reliably.
    connect(&m_hoverPollTimer, &QTimer::timeout, this, &MainWindow::pollHover);
    m_hoverPollTimer.start(Theme::kHoverPollMs);

    buildActions();
    buildStatusBar();

    const int firstTab = createTab();
    switchToTab(firstTab);

    loadSettings();
}

MainWindow::~MainWindow() = default;

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
    m_langLabel->setText(tab.highlighter->language());
    m_fileLabel->setText(tab.path.isEmpty() ? "untitled" : tab.path);
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

    if (tab.dirty) {
        if (m_activeTab != index) switchToTab(index);
        const auto resp = QMessageBox::question(this, "Unsaved Changes",
            QString("Discard unsaved changes in %1?")
                .arg(tab.path.isEmpty() ? "untitled" : QFileInfo(tab.path).fileName()),
            QMessageBox::Yes | QMessageBox::No);
        if (resp != QMessageBox::Yes) return;
    }

    const bool wasActive = (index == m_activeTab);
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
    m_topbar->setGeometry(0, m_topbar->isRevealed() ? 0 : -Theme::kBarHeight, width(),
                           Theme::kBarHeight);
    if (m_findBar) {
        const QSize hint = m_findBar->sizeHint();
        m_findBar->setGeometry(width() - hint.width() - 16, Theme::kTabHeight + 8,
                                hint.width(), hint.height());
    }
    applyRoundedMask();
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
        if (!m_topbar->isRevealed()) {
            m_topbar->reveal();
            m_topbar->raise();
        }
        m_topbar->setGeometry(0, 0, width(), Theme::kBarHeight);
    } else if (m_topbar->isRevealed() && !m_barHideTimer.isActive()) {
        scheduleBarHide();
    }
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
        "\u2318F find   [ ] glass opacity   \u2318+/- zoom   \u2318\u21e7O recent"));
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

void MainWindow::loadFile(const QString &path) {
    const bool reuse = m_activeTab >= 0 && currentTab().path.isEmpty() &&
                        !currentTab().dirty && m_editor->document()->isEmpty();
    if (!reuse) switchToTab(createTab());

    m_pendingLoadPath = path;
    m_editor->setReadOnly(true);
    m_editor->clear();
    m_fileLabel->setText(QString("loading %1...").arg(QFileInfo(path).fileName()));

    m_loadWorker = new FileLoadWorker(path, this);
    connect(m_loadWorker, &FileLoadWorker::chunkReady, this, &MainWindow::appendChunk);
    connect(m_loadWorker, &FileLoadWorker::finishedLoading, this, &MainWindow::finishLoad);
    connect(m_loadWorker, &FileLoadWorker::failed, this, &MainWindow::loadFailed);
    connect(m_loadWorker, &QThread::finished, m_loadWorker, &QObject::deleteLater);
    m_loadWorker->start();
}

void MainWindow::appendChunk(const QString &chunk) {
    QTextCursor cursor = m_editor->textCursor();
    cursor.movePosition(QTextCursor::End);
    cursor.insertText(chunk);
}

void MainWindow::finishLoad() {
    m_editor->setReadOnly(false);
    currentTab().path = m_pendingLoadPath;
    currentTab().dirty = false;
    m_editor->ensureTextVisible();
    currentTab().highlighter->setLanguageForPath(m_pendingLoadPath);
    m_langLabel->setText(currentTab().highlighter->language());
    m_fileLabel->setText(m_pendingLoadPath);
    setWindowTitle(QString("%1 \u2014 %2").arg(kAppName, QFileInfo(m_pendingLoadPath).fileName()));
    refreshTabLabel(m_activeTab);
    m_tabBar->setTabDirty(m_activeTab, false);
    addToRecentFiles(m_pendingLoadPath);
}

void MainWindow::loadFailed(const QString &message) {
    m_editor->setReadOnly(false);
    QMessageBox::critical(this, "Open File Failed", message);
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
    m_saveWorker = new FileSaveWorker(path, m_editor->toPlainText(), this);
    connect(m_saveWorker, &FileSaveWorker::finishedSaving, this,
            [this, path] { finishSave(path); });
    connect(m_saveWorker, &FileSaveWorker::failed, this, [this](const QString &msg) {
        QMessageBox::critical(this, "Save File Failed", msg);
    });
    connect(m_saveWorker, &QThread::finished, m_saveWorker, &QObject::deleteLater);
    m_saveWorker->start();
}

void MainWindow::finishSave(const QString &path) {
    currentTab().path = path;
    currentTab().dirty = false;
    m_tabBar->setTabDirty(m_activeTab, false);
    currentTab().highlighter->setLanguageForPath(path);
    m_langLabel->setText(currentTab().highlighter->language());
    m_fileLabel->setText(path);
    setWindowTitle(QString("%1 \u2014 %2").arg(kAppName, QFileInfo(path).fileName()));
    refreshTabLabel(m_activeTab);
    addToRecentFiles(path);
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
}

void MainWindow::saveSettings() {
    QSettings settings;
    settings.setValue("geometry", saveGeometry());
    settings.setValue("recentFiles", m_recentFiles);
    settings.setValue("glassAlpha", m_editor->backgroundAlpha());
}

void MainWindow::closeEvent(QCloseEvent *event) {
    for (const auto &tab : m_tabs) {
        if (tab.dirty) {
            const auto resp = QMessageBox::question(this, "Unsaved Changes",
                                                      "You have unsaved changes. Discard and quit?",
                                                      QMessageBox::Yes | QMessageBox::No);
            if (resp != QMessageBox::Yes) {
                event->ignore();
                return;
            }
            break;
        }
    }
    saveSettings();
    event->accept();
}
