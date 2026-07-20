#pragma once

#include <QPlainTextEdit>
#include <QWidget>
#include <QTimer>
#include <QColor>

class QResizeEvent;
class QPaintEvent;
class QFocusEvent;
class QWheelEvent;
class QMouseEvent;
class QKeyEvent;
class QTextDocument;

// Phosphor-green accent, shared across the gutter/editor/chrome.
inline const QColor kAccent(110, 231, 183);

class Editor;

class LineNumberArea : public QWidget {
    Q_OBJECT
public:
    explicit LineNumberArea(Editor *editor);
    QSize sizeHint() const override;

protected:
    void paintEvent(QPaintEvent *event) override;

private:
    Editor *m_editor;
};

// Animated "expand" caret. The timer only runs while the editor is focused
// and editable; each tick repaints just the caret's own rect (unioned with
// its previous position), never the whole viewport -- an idle/unfocused
// window costs nothing.
class CursorGlow : public QWidget {
    Q_OBJECT
public:
    explicit CursorGlow(Editor *editor);
    void start();
    void stop();
    bool isActive() const { return m_active; }

protected:
    void paintEvent(QPaintEvent *event) override;

private slots:
    void tick();

private:
    Editor *m_editor;
    QTimer m_timer;
    double m_phase = 0.0;
    QRect m_lastRect;
    bool m_active = false;
};

class Editor : public QPlainTextEdit {
    Q_OBJECT

public:
    explicit Editor(QWidget *parent = nullptr);

    void setBackgroundAlpha(int alpha);
    int backgroundAlpha() const { return m_alpha; }

    void zoomTextIn();
    void zoomTextOut();
    void resetTextZoom();
    int zoomLevel() const { return m_zoomLevel; }
    void setZoomLevel(int level);

    // Comment/uncomment every line touched by the current selection (or just
    // the current line, if there's no selection) using the given language's
    // line-comment prefix. No-op if the language has none (e.g. JSON).
    void toggleLineComment(const QString &prefix);

    void duplicateLine();
    void moveLineUp();
    void moveLineDown();
    void indentSelection(bool outdent);

    // Re-binds the explicit bright text color across the whole document.
    // Call after bulk content changes (e.g. finishing a chunked file load)
    // so newly inserted text can't end up relying on ambient palette
    // resolution for its color.
    void ensureTextVisible();

    // Swaps in a document belonging to a different tab and re-applies the
    // per-document formatting (line height, base text color) that would
    // otherwise only ever have been set up for the original document.
    void adoptDocument(QTextDocument *doc);

    int lineNumberAreaWidth() const;
    void paintLineNumbers(QPaintEvent *event);
    QSize lineNumberAreaSize() const;

signals:
    void opacityChanged(int alpha);

protected:
    void resizeEvent(QResizeEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;

private slots:
    void updateGutterWidth();
    void updateGutterArea(const QRect &rect, int dy);
    void onCursorMoved();

private:
    void applyPalette();
    void applyBaseTextFormat();
    void updateBracketMatch();

    LineNumberArea *m_gutter;
    CursorGlow *m_cursorGlow;
    int m_alpha;
    int m_zoomLevel = 0;

    friend class LineNumberArea;
};
