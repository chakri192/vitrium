#pragma once

#include <QMainWindow>
#include <QTimer>
#include <QVector>
#include <QQueue>
#include <QSet>
#include <QString>

class QFileSystemWatcher;

class Editor;
class Highlighter;
class AutoHideBar;
class FindBar;
class TabBar;
class FileLoadWorker;
class FileSaveWorker;
class QLabel;
class QStatusBar;
class QTextDocument;
class QDragEnterEvent;
class QDropEvent;

class MainWindow : public QMainWindow {
    Q_OBJECT

public:
    MainWindow();
    ~MainWindow() override;

    void loadFile(const QString &path);

protected:
    void showEvent(QShowEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    void closeEvent(QCloseEvent *event) override;
    void dragEnterEvent(QDragEnterEvent *event) override;
    void dropEvent(QDropEvent *event) override;

public slots:
    void openFile();
    void saveFile();
    void saveFileAs();
    void newTab();
    void closeCurrentTab();
    void nextTab();
    void previousTab();
    void setGlassOpacity(int alpha);
    void toggleMaximized();
    void cancelBarHide();
    void scheduleBarHide();
    void goToLine();
    void toggleWordWrap();
    void toggleComment();
    void duplicateLine();
    void moveLineUp();
    void moveLineDown();
    void closeOtherTabs();
    void closeAllTabs();

private slots:
    void onOpacityChanged(int alpha);
    void pollHover();
    void concealBar();
    void appendChunk(const QString &chunk);
    void finishLoad();
    void loadFailed(const QString &message);
    void finishSave(const QString &path);
    void markDirty();
    void updatePositionLabel();
    void activateTab(int index);
    void requestCloseTab(int index);
    void startNextLoad();
    void onFileChangedOnDisk(const QString &path);

private:
    struct DocumentTab {
        QString path;              // empty = untitled
        QTextDocument *document = nullptr;
        Highlighter *highlighter = nullptr;
        bool dirty = false;
        bool loading = false;
        int savedCursorPos = 0;
    };

    void buildActions();
    void buildStatusBar();
    void applyRoundedMask();
    void repositionFindBar();
    void saveTo(const QString &path);
    void openPath(const QString &path);
    int createTab(const QString &path = QString());
    void closeTabAt(int index);
    void switchToTab(int index);
    void refreshTabLabel(int index);
    void addToRecentFiles(const QString &path);
    void loadSettings();
    void saveSettings();
    DocumentTab &currentTab();
    int findTabForPath(const QString &path) const;
    // Synchronously (from the caller's point of view -- runs its own nested
    // event loop) saves a single tab. Used by the close-tab/quit confirmation
    // flows, where "Save" has to complete before the tab/window is allowed
    // to actually close.
    bool saveTabAndWait(int index);
    bool confirmDiscardOrSave(int index, const QString &verb);
    void watchPath(const QString &path);
    void unwatchPath(const QString &path);
    void reloadTab(int index);

    Editor *m_editor;
    AutoHideBar *m_topbar;
    FindBar *m_findBar;
    TabBar *m_tabBar;
    QTimer m_barHideTimer;
    QTimer m_hoverPollTimer;

    QLabel *m_langLabel;
    QLabel *m_fileLabel;
    QLabel *m_posLabel;

    QVector<DocumentTab> m_tabs;
    int m_activeTab = -1;
    QStringList m_recentFiles;

    // Loads are always run one-at-a-time (see startNextLoad()): the
    // currently-loading tab's index/path, plus everything still queued
    // behind it (from a multi-file drag-drop, multiple CLI args, or a
    // session restore). appendChunk() writes directly into
    // m_tabs[m_currentLoadTabIndex].document rather than into whatever
    // m_editor happens to be showing right now, so switching tabs mid-load
    // can't splice one file's contents into another's.
    struct QueuedLoad {
        QString path;
        int tabIndex;  // -1 = decide reuse-vs-new-tab when this load actually starts
    };
    QQueue<QueuedLoad> m_loadQueue;
    int m_currentLoadTabIndex = -1;
    QString m_currentLoadPath;
    bool m_currentLoadCreatedTab = false;

    FileLoadWorker *m_loadWorker = nullptr;
    FileSaveWorker *m_saveWorker = nullptr;
    QFileSystemWatcher *m_fsWatcher = nullptr;
    QSet<QString> m_selfWritePaths;
    bool m_wordWrap = false;
    void *m_effectView = nullptr;  // opaque NSVisualEffectView*, macOS only
};
