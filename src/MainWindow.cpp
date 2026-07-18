#include "MainWindow.h"
#include "Editor.h"
#include "Highlighter.h"
#include "AutoHideBar.h"
#include "FindBar.h"
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
#include <QKeySequence>
#include <QPainterPath>
#include <QRegion>
#include <QTextCursor>
#include <QFileInfo>
#include <QWindow>
#include <QSlider>
#include <QCursor>
#include <QtCore/qglobal.h>

namespace {
const char *kAppName = "Vitrum";
}

MainWindow::MainWindow() : QMainWindow(nullptr) {
    setWindowTitle(kAppName);
    resize(980, 680);

    // Frameless: no native title bar / traffic lights. Dragging + close +
    // minimize come from the hover-reveal AutoHideBar instead.
    setWindowFlag(Qt::FramelessWindowHint, true);
    setAttribute(Qt::WA_TranslucentBackground);
    setStyleSheet("QMainWindow { background: transparent; }");

    auto *container = new QWidget(this);
    auto *layout = new QVBoxLayout(container);
    layout->setContentsMargins(0, 0, 0, 0);
    setCentralWidget(container);

    m_editor = new Editor(container);
    layout->addWidget(m_editor);
    m_highlighter = new Highlighter(m_editor->document());

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
    // hover tracking doesn't handle reliably, and was the cause of the bar
    // vanishing as soon as the cursor reached it instead of staying revealed.
    connect(&m_hoverPollTimer, &QTimer::timeout, this, &MainWindow::pollHover);
    m_hoverPollTimer.start(Theme::kHoverPollMs);

    buildActions();
    buildStatusBar();
}

void MainWindow::showEvent(QShowEvent *event) {
    QMainWindow::showEvent(event);
#ifndef VITRUM_NO_MAC_VIBRANCY
    if (!m_effectView && qEnvironmentVariableIsSet("VITRUM_ENABLE_GLASS")) {
        if (QWindow *handle = windowHandle()) {
            m_effectView = MacVibrancy::installGlass(handle, Theme::kWindowRadius, "hud");
            // Fixed, not slider-driven: two independently-animated alpha
            // layers (this native blur view's alphaValue and Qt's own tint
            // fill) fighting each other at every slider position was the
            // likely cause of "solid" instead rendering as a near-invisible
            // wash of blur. The native blur now always renders at full
            // strength; the slider only controls the Qt-side tint on top of
            // it, which is a single, predictable variable instead of two.
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
        m_findBar->setGeometry(width() - hint.width() - 16, 16, hint.width(), hint.height());
    }
    applyRoundedMask();
}

void MainWindow::applyRoundedMask() {
    QPainterPath path;
    path.addRoundedRect(QRectF(rect()), Theme::kWindowRadius, Theme::kWindowRadius);
    setMask(QRegion(path.toFillPolygon().toPolygon()));
}

void MainWindow::setGlassOpacity(int alpha) {
    // Native blur alpha is intentionally NOT touched here anymore -- see the
    // comment in showEvent(). This is now the only thing the slider drives.
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
        // isActive() guard: without it, a still-hovering-but-not-in-zone
        // cursor would restart the singleShot timer every single poll tick
        // forever, and it would never actually fire.
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
    addAct("Quit", QKeySequence::Quit, &QWidget::close);

    // Glass opacity now lives on bracket keys -- Ctrl+=/Ctrl+- are freed up
    // for the far more standard "zoom text size" convention below instead.
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
    connect(findNextAct, &QAction::triggered, this, [this] {
        m_findBar->openFind();
    });
    addAction(findNextAct);
}

void MainWindow::buildStatusBar() {
    auto *sb = new QStatusBar(this);
    sb->setStyleSheet(QString(
        "QStatusBar { background: rgba(7, 9, 9, 235); color: #6E8A79; "
        "border-top: 1px solid rgba(%1, %2, %3, 40); font-size: 11px; }")
        .arg(kAccent.red()).arg(kAccent.green()).arg(kAccent.blue()));
    sb->setToolTip(QStringLiteral(
        "\u2318O open   \u2318S save   \u2318F find   [ ] glass opacity   \u2318+/- zoom"));
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
    m_dirty = true;
    const QString title = m_currentPath.isEmpty() ? "untitled" : QFileInfo(m_currentPath).fileName();
    // Dot instead of asterisk for the unsaved indicator -- a little more
    // refined/modern (matches the convention most native apps use now).
    setWindowTitle(QString("%1 \u2014 %2 \u25CF").arg(kAppName, title));
}

// --------------------------------------------------------- file operations

void MainWindow::openFile() {
    const QString path = QFileDialog::getOpenFileName(this, "Open File");
    if (path.isEmpty()) return;
    loadFile(path);
}

void MainWindow::loadFile(const QString &path) {
    m_editor->setReadOnly(true);
    m_editor->clear();
    m_fileLabel->setText(QString("loading %1...").arg(QFileInfo(path).fileName()));

    m_loadWorker = new FileLoadWorker(path, this);
    connect(m_loadWorker, &FileLoadWorker::chunkReady, this, &MainWindow::appendChunk);
    connect(m_loadWorker, &FileLoadWorker::finishedLoading, this,
            [this, path] { finishLoad(path); });
    connect(m_loadWorker, &FileLoadWorker::failed, this, &MainWindow::loadFailed);
    connect(m_loadWorker, &QThread::finished, m_loadWorker, &QObject::deleteLater);
    m_loadWorker->start();
}

void MainWindow::appendChunk(const QString &chunk) {
    QTextCursor cursor = m_editor->textCursor();
    cursor.movePosition(QTextCursor::End);
    cursor.insertText(chunk);
}

void MainWindow::finishLoad(const QString &path) {
    m_editor->setReadOnly(false);
    m_currentPath = path;
    m_editor->ensureTextVisible();
    m_highlighter->setLanguageForPath(path);
    m_langLabel->setText(m_highlighter->language());
    m_fileLabel->setText(path);
    setWindowTitle(QString("%1 \u2014 %2").arg(kAppName, QFileInfo(path).fileName()));
    m_dirty = false;
}

void MainWindow::loadFailed(const QString &message) {
    m_editor->setReadOnly(false);
    QMessageBox::critical(this, "Open File Failed", message);
}

void MainWindow::saveFile() {
    if (m_currentPath.isEmpty()) {
        saveFileAs();
        return;
    }
    saveTo(m_currentPath);
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
    m_currentPath = path;
    m_highlighter->setLanguageForPath(path);
    m_langLabel->setText(m_highlighter->language());
    m_fileLabel->setText(path);
    setWindowTitle(QString("%1 \u2014 %2").arg(kAppName, QFileInfo(path).fileName()));
    m_dirty = false;
}

void MainWindow::closeEvent(QCloseEvent *event) {
    if (m_dirty) {
        const auto resp = QMessageBox::question(this, "Unsaved Changes",
                                                  "Discard unsaved changes and quit?",
                                                  QMessageBox::Yes | QMessageBox::No);
        if (resp != QMessageBox::Yes) {
            event->ignore();
            return;
        }
    }
    event->accept();
}
