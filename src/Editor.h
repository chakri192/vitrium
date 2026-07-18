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

    // Re-binds the explicit bright text color across the whole document.
    // Call after bulk content changes (e.g. finishing a chunked file load)
    // so newly inserted text can't end up relying on ambient palette
    // resolution for its color.
    void ensureTextVisible();

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

private slots:
    void updateGutterWidth();
    void updateGutterArea(const QRect &rect, int dy);
    void onCursorMoved();

private:
    void applyPalette();
    void applyLineHeight(double factor);
    void applyBaseTextFormat();

    LineNumberArea *m_gutter;
    CursorGlow *m_cursorGlow;
    int m_alpha;
    int m_zoomLevel = 0;

    friend class LineNumberArea;
};
