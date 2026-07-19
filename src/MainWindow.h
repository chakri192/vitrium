#pragma once

#include <QMainWindow>
#include <QTimer>
#include <QVector>
#include <QString>

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

private:
    struct DocumentTab {
        QString path;              // empty = untitled
        QTextDocument *document = nullptr;
        Highlighter *highlighter = nullptr;
        bool dirty = false;
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
    QString m_pendingLoadPath;

    FileLoadWorker *m_loadWorker = nullptr;
    FileSaveWorker *m_saveWorker = nullptr;
    void *m_effectView = nullptr;  // opaque NSVisualEffectView*, macOS only
};
