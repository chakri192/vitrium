#pragma once

#include <QMainWindow>
#include <QTimer>

class Editor;
class Highlighter;
class AutoHideBar;
class FindBar;
class FileLoadWorker;
class FileSaveWorker;
class QLabel;
class QStatusBar;

class MainWindow : public QMainWindow {
    Q_OBJECT

public:
    MainWindow();

    void loadFile(const QString &path);

protected:
    void showEvent(QShowEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    void closeEvent(QCloseEvent *event) override;

public slots:
    void openFile();
    void saveFile();
    void saveFileAs();
    void setGlassOpacity(int alpha);
    void toggleMaximized();
    void cancelBarHide();
    void scheduleBarHide();

private slots:
    void onOpacityChanged(int alpha);
    void pollHover();
    void concealBar();
    void appendChunk(const QString &chunk);
    void finishLoad(const QString &path);
    void loadFailed(const QString &message);
    void finishSave(const QString &path);
    void markDirty();
    void updatePositionLabel();

private:
    void buildActions();
    void buildStatusBar();
    void applyRoundedMask();
    void saveTo(const QString &path);

    Editor *m_editor;
    Highlighter *m_highlighter;
    AutoHideBar *m_topbar;
    FindBar *m_findBar;
    QTimer m_barHideTimer;
    QTimer m_hoverPollTimer;

    QLabel *m_langLabel;
    QLabel *m_fileLabel;
    QLabel *m_posLabel;

    QString m_currentPath;
    bool m_dirty = false;

    FileLoadWorker *m_loadWorker = nullptr;
    FileSaveWorker *m_saveWorker = nullptr;
    void *m_effectView = nullptr;  // opaque NSVisualEffectView*, macOS only
};
