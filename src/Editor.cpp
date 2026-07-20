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
#include <QTextEdit>
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
constexpr int kViewportVPad = 14;  // top/bottom viewport padding -- the gutter
                                    // must be offset by the SAME amount, or its
                                    // paint coordinates (viewport-relative) end
                                    // up misaligned against its own widget-
                                    // relative geometry by exactly this much

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
    setViewportMargins(48, kViewportVPad, 14, kViewportVPad);
    setCursorWidth(0);  // native caret replaced by CursorGlow

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
    if ((event->key() == Qt::Key_Tab || event->key() == Qt::Key_Backtab) &&
        textCursor().hasSelection()) {
        indentSelection(event->key() == Qt::Key_Backtab || (event->modifiers() & Qt::ShiftModifier));
        return;
    }

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

void Editor::updateGutterWidth() { setViewportMargins(lineNumberAreaWidth() + 8, kViewportVPad, 14, kViewportVPad); }

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
    // Offset by kViewportVPad to match where the viewport itself actually
    // starts -- without this the gutter's own widget-relative y=0 sits
    // kViewportVPad above the viewport's y=0, but the block positions used
    // to paint line numbers are viewport-relative, so every number was
    // rendered kViewportVPad too high relative to its real text row.
    m_gutter->setGeometry(QRect(cr.left(), cr.top() + kViewportVPad, lineNumberAreaWidth(),
                                 cr.height() - kViewportVPad));
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

void Editor::setZoomLevel(int level) {
    if (level > m_zoomLevel)
        zoomIn(level - m_zoomLevel);
    else if (level < m_zoomLevel)
        zoomOut(m_zoomLevel - level);
    m_zoomLevel = level;
}

void Editor::onCursorMoved() {
    // No full-row highlight -- the gutter tick above is the only current-line
    // indicator, so just repaint the (cheap, thin) gutter strip.
    m_gutter->update();
    updateBracketMatch();
}

void Editor::updateBracketMatch() {
    QTextDocument *doc = document();
    const QTextCursor cursor = textCursor();

    auto matchFor = [](QChar c) -> QChar {
        switch (c.unicode()) {
            case '(': return ')';
            case ')': return '(';
            case '[': return ']';
            case ']': return '[';
            case '{': return '}';
            case '}': return '{';
            default: return QChar();
        }
    };
    auto isOpener = [](QChar c) { return c == '(' || c == '[' || c == '{'; };

    const int pos = cursor.position();
    const QChar charAfter = pos < doc->characterCount() - 1 ? doc->characterAt(pos) : QChar();
    const QChar charBefore = pos > 0 ? doc->characterAt(pos - 1) : QChar();

    QChar bracketChar;
    int bracketPos = -1;
    if (!matchFor(charAfter).isNull()) {
        bracketChar = charAfter;
        bracketPos = pos;
    } else if (!matchFor(charBefore).isNull()) {
        bracketChar = charBefore;
        bracketPos = pos - 1;
    }

    QList<QTextEdit::ExtraSelection> selections;
    if (bracketPos >= 0) {
        const QChar target = matchFor(bracketChar);
        const bool forward = isOpener(bracketChar);
        int depth = 0;
        int matchPos = -1;
        if (forward) {
            for (int i = bracketPos; i < doc->characterCount() - 1; ++i) {
                const QChar c = doc->characterAt(i);
                if (c == bracketChar) ++depth;
                else if (c == target && --depth == 0) { matchPos = i; break; }
            }
        } else {
            for (int i = bracketPos; i >= 0; --i) {
                const QChar c = doc->characterAt(i);
                if (c == bracketChar) ++depth;
                else if (c == target && --depth == 0) { matchPos = i; break; }
            }
        }

        if (matchPos >= 0) {
            QColor hi = kAccent;
            hi.setAlpha(90);
            for (int p : {bracketPos, matchPos}) {
                QTextEdit::ExtraSelection sel;
                sel.format.setBackground(hi);
                QTextCursor c(doc);
                c.setPosition(p);
                c.setPosition(p + 1, QTextCursor::KeepAnchor);
                sel.cursor = c;
                selections.append(sel);
            }
        }
    }
    setExtraSelections(selections);
}

void Editor::toggleLineComment(const QString &prefix) {
    if (prefix.isEmpty()) return;  // language has no line-comment syntax

    QTextCursor sel = textCursor();
    int startBlock, endBlock;
    if (sel.hasSelection()) {
        QTextCursor startC(document());
        startC.setPosition(sel.selectionStart());
        QTextCursor endC(document());
        endC.setPosition(sel.selectionEnd());
        startBlock = startC.blockNumber();
        endBlock = endC.blockNumber();
        if (endC.positionInBlock() == 0 && endBlock > startBlock) --endBlock;
    } else {
        startBlock = endBlock = sel.blockNumber();
    }

    QTextDocument *doc = document();
    bool allCommented = true;
    for (int b = startBlock; b <= endBlock; ++b) {
        const QString trimmed = doc->findBlockByNumber(b).text().trimmed();
        if (trimmed.isEmpty()) continue;
        if (!trimmed.startsWith(prefix)) { allCommented = false; break; }
    }

    QTextCursor editCursor(doc);
    editCursor.beginEditBlock();
    for (int b = startBlock; b <= endBlock; ++b) {
        QTextBlock block = doc->findBlockByNumber(b);
        const QString text = block.text();
        QTextCursor bc(block);
        if (allCommented) {
            const int idx = text.indexOf(prefix);
            if (idx < 0) continue;
            int removeLen = prefix.length();
            if (idx + removeLen < text.length() && text.at(idx + removeLen) == ' ') ++removeLen;
            bc.setPosition(block.position() + idx);
            bc.setPosition(block.position() + idx + removeLen, QTextCursor::KeepAnchor);
            bc.removeSelectedText();
        } else {
            if (text.trimmed().isEmpty()) continue;  // don't comment blank lines
            bc.setPosition(block.position());
            bc.insertText(prefix + " ");
        }
    }
    editCursor.endEditBlock();
}

void Editor::duplicateLine() {
    QTextCursor cursor = textCursor();
    const int col = cursor.positionInBlock();
    const int blockNum = cursor.blockNumber();

    cursor.movePosition(QTextCursor::StartOfBlock);
    cursor.movePosition(QTextCursor::EndOfBlock, QTextCursor::KeepAnchor);
    const QString lineText = cursor.selectedText();

    cursor.beginEditBlock();
    cursor.movePosition(QTextCursor::EndOfBlock);
    cursor.insertText("\n" + lineText);
    cursor.endEditBlock();

    QTextCursor result(document()->findBlockByNumber(blockNum + 1));
    result.movePosition(QTextCursor::NextCharacter, QTextCursor::MoveAnchor,
                         qMin(col, result.block().length() - 1));
    setTextCursor(result);
}

void Editor::moveLineUp() {
    QTextCursor cursor = textCursor();
    const int blockNum = cursor.blockNumber();
    if (blockNum == 0) return;
    const int col = cursor.positionInBlock();

    QTextBlock curBlock = document()->findBlockByNumber(blockNum);
    QTextBlock prevBlock = curBlock.previous();
    const QString curText = curBlock.text();
    const QString prevText = prevBlock.text();

    QTextCursor edit(document());
    edit.beginEditBlock();
    edit.setPosition(prevBlock.position());
    edit.setPosition(curBlock.position() + curBlock.length() - 1, QTextCursor::KeepAnchor);
    edit.removeSelectedText();
    edit.insertText(curText + "\n" + prevText);
    edit.endEditBlock();

    QTextCursor result(document()->findBlockByNumber(blockNum - 1));
    result.movePosition(QTextCursor::NextCharacter, QTextCursor::MoveAnchor,
                         qMin(col, result.block().length() - 1));
    setTextCursor(result);
}

void Editor::moveLineDown() {
    QTextCursor cursor = textCursor();
    const int blockNum = cursor.blockNumber();
    if (blockNum >= document()->blockCount() - 1) return;
    const int col = cursor.positionInBlock();

    QTextBlock curBlock = document()->findBlockByNumber(blockNum);
    QTextBlock nextBlock = curBlock.next();
    const QString curText = curBlock.text();
    const QString nextText = nextBlock.text();

    QTextCursor edit(document());
    edit.beginEditBlock();
    edit.setPosition(curBlock.position());
    edit.setPosition(nextBlock.position() + nextBlock.length() - 1, QTextCursor::KeepAnchor);
    edit.removeSelectedText();
    edit.insertText(nextText + "\n" + curText);
    edit.endEditBlock();

    QTextCursor result(document()->findBlockByNumber(blockNum + 1));
    result.movePosition(QTextCursor::NextCharacter, QTextCursor::MoveAnchor,
                         qMin(col, result.block().length() - 1));
    setTextCursor(result);
}

void Editor::indentSelection(bool outdent) {
    QTextCursor sel = textCursor();
    QTextCursor startC(document());
    startC.setPosition(sel.selectionStart());
    QTextCursor endC(document());
    endC.setPosition(sel.selectionEnd());
    int startBlock = startC.blockNumber();
    int endBlock = endC.blockNumber();
    if (endC.positionInBlock() == 0 && endBlock > startBlock) --endBlock;

    QTextCursor edit(document());
    edit.beginEditBlock();
    for (int b = startBlock; b <= endBlock; ++b) {
        QTextBlock block = document()->findBlockByNumber(b);
        QTextCursor bc(block);
        if (outdent) {
            const QString text = block.text();
            int removeCount = 0;
            if (text.startsWith('\t')) {
                removeCount = 1;
            } else {
                while (removeCount < 4 && removeCount < text.length() && text.at(removeCount) == ' ')
                    ++removeCount;
            }
            if (removeCount > 0) {
                bc.setPosition(block.position());
                bc.setPosition(block.position() + removeCount, QTextCursor::KeepAnchor);
                bc.removeSelectedText();
            }
        } else {
            bc.setPosition(block.position());
            bc.insertText("    ");
        }
    }
    edit.endEditBlock();
}
