#include "Editor.h"
#include "Theme.h"

#include <QPainter>
#include <QLinearGradient>
#include <QFontDatabase>
#include <QTextBlockFormat>
#include <QTextCharFormat>
#include <QTextBlock>
#include <QTextCursor>
#include <QPalette>
#include <QWheelEvent>
#include <QMouseEvent>
#include <QKeyEvent>
#include <QTextDocument>
#include <cmath>
#include <algorithm>

namespace {

QFont pickMonoFont(qreal pointSize = 13.5) {
    static const QStringList candidates = {"JetBrains Mono", "Menlo", "Monaco", "Courier New"};
    QFont font;
    for (const auto &name : candidates) {
        QFont candidate(name);
        if (QFontInfo(candidate).exactMatch()) {
            font = candidate;
            break;
        }
    }
    if (font.family().isEmpty()) font.setFamily(candidates.first());
    font.setStyleHint(QFont::Monospace);
    font.setFixedPitch(true);
    font.setPointSizeF(pointSize);
    return font;
}

const QColor kBaseBg(12, 15, 16);
const QColor kTextFg(242, 250, 246, 255);
const QColor kGutterBg(7, 9, 9, 250);
const QColor kGutterDim(90, 120, 108, 255);
const QColor kGutterActive(146, 255, 214, 255);

}  // namespace

// ---------------------------------------------------------------- gutter --

LineNumberArea::LineNumberArea(Editor *editor) : QWidget(editor), m_editor(editor) {}

QSize LineNumberArea::sizeHint() const { return m_editor->lineNumberAreaSize(); }

void LineNumberArea::paintEvent(QPaintEvent *event) { m_editor->paintLineNumbers(event); }

// ------------------------------------------------------------ cursor glow --

CursorGlow::CursorGlow(Editor *editor) : QWidget(editor->viewport()), m_editor(editor) {
    setAttribute(Qt::WA_TransparentForMouseEvents);
    setAttribute(Qt::WA_TranslucentBackground);
    connect(&m_timer, &QTimer::timeout, this, &CursorGlow::tick);
    hide();
}

void CursorGlow::start() {
    if (m_active) return;
    m_active = true;
    m_lastRect = m_editor->cursorRect().adjusted(-5, -1, 5, 1);
    m_timer.start(33);  // ~30fps -- plenty smooth for a slow breathing pulse
    show();
}

void CursorGlow::stop() {
    m_active = false;
    m_timer.stop();
    hide();
}

void CursorGlow::tick() {
    if (m_editor->isReadOnly() || !m_editor->hasFocus()) return;
    m_phase += 0.10;
    const QRect cur = m_editor->cursorRect().adjusted(-5, -1, 5, 1);
    update(cur.united(m_lastRect));
    m_lastRect = cur;
}

void CursorGlow::paintEvent(QPaintEvent *) {
    if (!m_active || m_editor->isReadOnly() || !m_editor->hasFocus()) return;
    const QRectF rect = m_editor->cursorRect();
    const double t = (std::sin(m_phase) + 1) / 2;  // 0..1 breathing pulse

    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);

    // Soft glow halo, widest at the core and fading fully transparent at
    // the edges -- replaces the old flat expanding-rectangle look.
    const qreal glowHalfWidth = 4.5;
    QLinearGradient glow(rect.x() - glowHalfWidth, 0, rect.x() + glowHalfWidth, 0);
    QColor edge = kAccent; edge.setAlpha(0);
    QColor mid = kAccent; mid.setAlpha(static_cast<int>(35 + 55 * t));
    glow.setColorAt(0.0, edge);
    glow.setColorAt(0.5, mid);
    glow.setColorAt(1.0, edge);
    painter.fillRect(QRectF(rect.x() - glowHalfWidth, rect.y(), glowHalfWidth * 2, rect.height()),
                      glow);

    // Slim, crisp core beam on top -- this is the actual caret.
    QColor core = kAccent;
    core.setAlpha(static_cast<int>(190 + 65 * t));
    QRectF beam(rect.x() - 0.75, rect.y() + 1, 1.5, rect.height() - 2);
    painter.setPen(Qt::NoPen);
    painter.setBrush(core);
    painter.drawRoundedRect(beam, 0.75, 0.75);
}

// -------------------------------------------------------------- editor ----

Editor::Editor(QWidget *parent) : QPlainTextEdit(parent), m_alpha(Theme::kDefaultAlpha) {
    setMouseTracking(true);

    setFont(pickMonoFont());
    setLineWrapMode(QPlainTextEdit::NoWrap);
    setTabStopDistance(4 * fontMetrics().horizontalAdvance(' '));
    setFrameStyle(0);
    setViewportMargins(48, 14, 14, 14);
    setCursorWidth(0);  // native caret replaced by CursorGlow

    applyLineHeight(1.8);
    applyBaseTextFormat();
    QTextCharFormat liveFmt;
    liveFmt.setForeground(kTextFg);
    mergeCurrentCharFormat(liveFmt);

    m_gutter = new LineNumberArea(this);
    m_cursorGlow = new CursorGlow(this);

    connect(this, &QPlainTextEdit::blockCountChanged, this, &Editor::updateGutterWidth);
    connect(this, &QPlainTextEdit::updateRequest, this, &Editor::updateGutterArea);
    connect(this, &QPlainTextEdit::cursorPositionChanged, this, &Editor::onCursorMoved);
    updateGutterWidth();
    onCursorMoved();

    applyPalette();

    setStyleSheet(QString(
        "QPlainTextEdit { border: 1px solid rgba(%1, %2, %3, 70); border-radius: %4px; }")
        .arg(kAccent.red()).arg(kAccent.green()).arg(kAccent.blue()).arg(Theme::kWindowRadius));
}

void Editor::focusInEvent(QFocusEvent *event) {
    QPlainTextEdit::focusInEvent(event);
    if (!isReadOnly()) m_cursorGlow->start();
}

void Editor::focusOutEvent(QFocusEvent *event) {
    QPlainTextEdit::focusOutEvent(event);
    m_cursorGlow->stop();
}

void Editor::applyLineHeight(double factor) {
    QTextCursor cursor(document());
    cursor.select(QTextCursor::Document);
    QTextBlockFormat blockFmt;
    blockFmt.setLineHeight(factor * 100, QTextBlockFormat::ProportionalHeight);
    cursor.mergeBlockFormat(blockFmt);
}

void Editor::applyBaseTextFormat() {
    // Explicit, not palette-derived: plain/unhighlighted text (e.g. a fresh
    // untitled file, before any QSyntaxHighlighter rule has ever matched
    // anything in it) has no per-character format of its own and would
    // otherwise fall back to whatever the ambient palette resolves to for
    // QPalette::Text -- which is exactly the text-disappears case. Binding
    // the color straight to the document's default character format makes
    // it deterministic regardless of platform/style palette quirks.
    QTextCursor cursor(document());
    cursor.select(QTextCursor::Document);
    QTextCharFormat baseFmt;
    baseFmt.setForeground(kTextFg);
    cursor.mergeCharFormat(baseFmt);
}

void Editor::setBackgroundAlpha(int alpha) {
    m_alpha = std::clamp(alpha, Theme::kMinAlpha, Theme::kMaxAlpha);
    applyPalette();
    emit opacityChanged(m_alpha);
}

void Editor::applyPalette() {
    QColor bg = kBaseBg;
    bg.setAlpha(m_alpha);
    QPalette pal = palette();
    pal.setColor(backgroundRole(), bg);
    pal.setColor(QPalette::Base, bg);
    pal.setColor(QPalette::Text, kTextFg);
    setPalette(pal);
    setAutoFillBackground(true);
    viewport()->setAutoFillBackground(true);
    QPalette vpPal = viewport()->palette();
    vpPal.setColor(QPalette::Base, bg);
    vpPal.setColor(QPalette::Window, bg);
    viewport()->setPalette(vpPal);
}

namespace {
const QString kOpeners = "([{\"'";
const QString kClosers = ")]}\"'";

QChar matchingCloser(QChar opener) {
    switch (opener.unicode()) {
        case '(': return ')';
        case '[': return ']';
        case '{': return '}';
        case '"': return '"';
        case '\'': return '\'';
        default: return QChar();
    }
}
}  // namespace

void Editor::keyPressEvent(QKeyEvent *event) {
    // Skip-over: typing a closer right where one already sits just moves
    // past it instead of inserting a duplicate.
    if (kClosers.contains(event->text()) && !event->text().isEmpty()) {
        QTextCursor c = textCursor();
        QTextDocument *doc = document();
        if (c.position() < doc->characterCount() - 1) {
            QTextCursor peek = c;
            peek.movePosition(QTextCursor::NextCharacter, QTextCursor::KeepAnchor);
            if (peek.selectedText() == event->text()) {
                c.movePosition(QTextCursor::NextCharacter);
                setTextCursor(c);
                return;
            }
        }
    }

    // Auto-close: typing an opener inserts its matching closer right after
    // the cursor, cursor stays between them.
    if (kOpeners.contains(event->text()) && !event->text().isEmpty() && !textCursor().hasSelection()) {
        const QChar opener = event->text().at(0);
        const QChar closer = matchingCloser(opener);
        if (!closer.isNull()) {
            QTextCursor c = textCursor();
            c.insertText(QString(opener) + QString(closer));
            c.movePosition(QTextCursor::PreviousCharacter);
            setTextCursor(c);
            return;
        }
    }

    // Auto-indent: new line carries the current line's leading whitespace
    // forward, with one extra indent level if the line ends on an opener.
    if (event->key() == Qt::Key_Return || event->key() == Qt::Key_Enter) {
        QTextCursor c = textCursor();
        const QString lineText = c.block().text();
        QString indent;
        for (QChar ch : lineText) {
            if (ch == ' ' || ch == '\t')
                indent += ch;
            else
                break;
        }
        const QString trimmed = lineText.trimmed();
        const bool endsOnOpener = !trimmed.isEmpty() && kOpeners.left(3).contains(trimmed.back());
        QPlainTextEdit::keyPressEvent(event);
        QString newIndent = indent;
        if (endsOnOpener) newIndent += "    ";
        if (!newIndent.isEmpty()) {
            QTextCursor after = textCursor();
            after.insertText(newIndent);
            setTextCursor(after);
        }
        return;
    }

    QPlainTextEdit::keyPressEvent(event);
}

void Editor::wheelEvent(QWheelEvent *event) {
    if (event->modifiers() & Qt::ControlModifier) {
        const int step = event->angleDelta().y() > 0 ? 10 : -10;
        setBackgroundAlpha(m_alpha + step);
        event->accept();
    } else {
        QPlainTextEdit::wheelEvent(event);
    }
}

int Editor::lineNumberAreaWidth() const {
    int digits = std::max(2, static_cast<int>(QString::number(std::max(1, blockCount())).length()));
    return 14 + fontMetrics().horizontalAdvance('9') * digits;
}

QSize Editor::lineNumberAreaSize() const { return QSize(lineNumberAreaWidth(), height()); }

void Editor::updateGutterWidth() { setViewportMargins(lineNumberAreaWidth() + 8, 14, 14, 14); }

void Editor::updateGutterArea(const QRect &rect, int dy) {
    if (dy)
        m_gutter->scroll(0, dy);
    else
        m_gutter->update(0, rect.y(), m_gutter->width(), rect.height());
    if (rect.contains(viewport()->rect())) updateGutterWidth();
}

void Editor::resizeEvent(QResizeEvent *event) {
    QPlainTextEdit::resizeEvent(event);
    const QRect cr = contentsRect();
    m_gutter->setGeometry(QRect(cr.left(), cr.top(), lineNumberAreaWidth(), cr.height()));
    m_cursorGlow->setGeometry(viewport()->rect());
}

void Editor::paintLineNumbers(QPaintEvent *event) {
    QPainter painter(m_gutter);
    // Tracks the same slider as the text panel now (previously fixed at a
    // constant alpha regardless of the slider) -- that's what caused the
    // "transparency isn't uniform" look: the gutter and the body visibly
    // diverged as you dragged, instead of moving together. Floor of 90 keeps
    // line numbers legible even at the most transparent end of the range.
    QColor gutterBg = kGutterBg;
    gutterBg.setAlpha(std::clamp(m_alpha + 55, 90, 255));
    painter.fillRect(event->rect(), gutterBg);

    const int currentLine = textCursor().blockNumber();
    QTextBlock block = firstVisibleBlock();
    int blockNumber = block.blockNumber();
    qreal top = blockBoundingGeometry(block).translated(contentOffset()).top();
    qreal bottom = top + blockBoundingRect(block).height();
    const int width = m_gutter->width();

    while (block.isValid() && top <= event->rect().bottom()) {
        if (block.isVisible() && bottom >= event->rect().top()) {
            const bool isCurrent = blockNumber == currentLine;
            if (isCurrent) {
                QColor tick = kAccent;
                tick.setAlpha(220);
                painter.fillRect(width - 4, static_cast<int>(top), 3,
                                  static_cast<int>(bottom - top), tick);
            }
            painter.setPen(isCurrent ? kGutterActive : kGutterDim);
            painter.drawText(0, static_cast<int>(top), width - 10, fontMetrics().height(),
                              Qt::AlignRight, QString::number(blockNumber + 1));
        }
        block = block.next();
        top = bottom;
        bottom = top + blockBoundingRect(block).height();
        ++blockNumber;
    }
}

void Editor::ensureTextVisible() { applyBaseTextFormat(); }

void Editor::adoptDocument(QTextDocument *doc) {
    setDocument(doc);
    applyLineHeight(1.8);
    ensureTextVisible();
}

void Editor::zoomTextIn() {
    zoomIn(1);
    ++m_zoomLevel;
}

void Editor::zoomTextOut() {
    zoomOut(1);
    --m_zoomLevel;
}

void Editor::resetTextZoom() {
    if (m_zoomLevel > 0)
        zoomOut(m_zoomLevel);
    else if (m_zoomLevel < 0)
        zoomIn(-m_zoomLevel);
    m_zoomLevel = 0;
}

void Editor::onCursorMoved() {
    // No full-row highlight -- the gutter tick above is the only current-line
    // indicator, so just repaint the (cheap, thin) gutter strip.
    m_gutter->update();
}
