#include "FindBar.h"
#include "Editor.h"  // kAccent

#include <QLineEdit>
#include <QLabel>
#include <QPushButton>
#include <QHBoxLayout>
#include <QVBoxLayout>
#include <QPlainTextEdit>
#include <QTextCursor>
#include <QTextDocument>
#include <QKeyEvent>

FindBar::FindBar(QPlainTextEdit *target, QWidget *parent)
    : QWidget(parent), m_target(target) {
    setAttribute(Qt::WA_StyledBackground, true);
    setStyleSheet(QString(
        "FindBar { background: rgba(9, 11, 12, 235); border: 1px solid rgba(%1, %2, %3, 70); "
        "border-radius: 10px; }"
        "QLineEdit { background: rgba(20, 24, 24, 220); color: #F2FAF6; border: 1px solid "
        "rgba(255,255,255,25); border-radius: 6px; padding: 4px 8px; font-size: 12px; }"
        "QPushButton { color: #C9D6CE; background: transparent; border: none; padding: 4px 8px; "
        "font-size: 12px; }"
        "QPushButton:hover { color: rgb(%1, %2, %3); }")
        .arg(kAccent.red()).arg(kAccent.green()).arg(kAccent.blue()));
    buildContents();
    hide();
}

void FindBar::buildContents() {
    auto *outer = new QVBoxLayout(this);
    outer->setContentsMargins(10, 8, 10, 8);
    outer->setSpacing(6);

    auto *searchRow = new QHBoxLayout();
    m_searchField = new QLineEdit(this);
    m_searchField->setPlaceholderText("Find");
    m_searchField->setFixedWidth(180);
    connect(m_searchField, &QLineEdit::returnPressed, this, &FindBar::findNext);
    searchRow->addWidget(m_searchField);

    auto *prevBtn = new QPushButton("\u2191", this);
    prevBtn->setToolTip("Previous match (Shift+Enter)");
    connect(prevBtn, &QPushButton::clicked, this, &FindBar::findPrev);
    auto *nextBtn = new QPushButton("\u2193", this);
    nextBtn->setToolTip("Next match (Enter)");
    connect(nextBtn, &QPushButton::clicked, this, &FindBar::findNext);
    searchRow->addWidget(prevBtn);
    searchRow->addWidget(nextBtn);

    m_replaceToggleBtn = new QPushButton("Replace", this);
    connect(m_replaceToggleBtn, &QPushButton::clicked, this, &FindBar::toggleReplaceRow);
    searchRow->addWidget(m_replaceToggleBtn);

    m_statusLabel = new QLabel(this);
    m_statusLabel->setStyleSheet("color: #7C8A82; font-size: 11px; background: transparent;");
    searchRow->addWidget(m_statusLabel);
    searchRow->addStretch(1);

    auto *closeBtn = new QPushButton("\u2715", this);
    closeBtn->setToolTip("Close (Esc)");
    connect(closeBtn, &QPushButton::clicked, this, &FindBar::closeBar);
    searchRow->addWidget(closeBtn);

    outer->addLayout(searchRow);

    m_replaceRow = new QWidget(this);
    auto *replaceLayout = new QHBoxLayout(m_replaceRow);
    replaceLayout->setContentsMargins(0, 0, 0, 0);
    m_replaceField = new QLineEdit(m_replaceRow);
    m_replaceField->setPlaceholderText("Replace with");
    m_replaceField->setFixedWidth(180);
    connect(m_replaceField, &QLineEdit::returnPressed, this, &FindBar::doReplace);
    replaceLayout->addWidget(m_replaceField);

    auto *replaceBtn = new QPushButton("Replace", m_replaceRow);
    connect(replaceBtn, &QPushButton::clicked, this, &FindBar::doReplace);
    auto *replaceAllBtn = new QPushButton("Replace All", m_replaceRow);
    connect(replaceAllBtn, &QPushButton::clicked, this, &FindBar::doReplaceAll);
    replaceLayout->addWidget(replaceBtn);
    replaceLayout->addWidget(replaceAllBtn);
    replaceLayout->addStretch(1);

    outer->addWidget(m_replaceRow);
    m_replaceRow->hide();

    connect(m_searchField, &QLineEdit::textChanged, this, [this](const QString &) {
        m_statusLabel->clear();
    });
}

void FindBar::openFind() {
    m_replaceRow->hide();
    show();
    raise();
    m_searchField->setFocus();
    m_searchField->selectAll();
}

void FindBar::openReplace() {
    show();
    raise();
    m_replaceRow->show();
    m_searchField->setFocus();
    m_searchField->selectAll();
}

void FindBar::toggleReplaceRow() {
    m_replaceRow->setVisible(!m_replaceRow->isVisible());
}

void FindBar::closeBar() {
    hide();
    m_target->setFocus();
}

void FindBar::keyPressEvent(QKeyEvent *event) {
    if (event->key() == Qt::Key_Escape) {
        closeBar();
        return;
    }
    QWidget::keyPressEvent(event);
}

void FindBar::updateStatus(bool found) {
    m_statusLabel->setText(found ? QString() : "no matches");
}

void FindBar::findNext() {
    const QString text = m_searchField->text();
    if (text.isEmpty()) return;
    bool found = m_target->find(text);
    if (!found) {
        QTextCursor c = m_target->textCursor();
        c.movePosition(QTextCursor::Start);
        m_target->setTextCursor(c);
        found = m_target->find(text);
    }
    updateStatus(found);
}

void FindBar::findPrev() {
    const QString text = m_searchField->text();
    if (text.isEmpty()) return;
    bool found = m_target->find(text, QTextDocument::FindBackward);
    if (!found) {
        QTextCursor c = m_target->textCursor();
        c.movePosition(QTextCursor::End);
        m_target->setTextCursor(c);
        found = m_target->find(text, QTextDocument::FindBackward);
    }
    updateStatus(found);
}

void FindBar::doReplace() {
    const QString text = m_searchField->text();
    if (text.isEmpty()) return;
    QTextCursor c = m_target->textCursor();
    if (c.hasSelection() && c.selectedText() == text) {
        c.insertText(m_replaceField->text());
        m_target->setTextCursor(c);
    }
    findNext();
}

void FindBar::doReplaceAll() {
    const QString text = m_searchField->text();
    const QString replacement = m_replaceField->text();
    if (text.isEmpty()) return;

    QTextCursor cursor(m_target->document());
    cursor.movePosition(QTextCursor::Start);
    m_target->setTextCursor(cursor);

    int count = 0;
    while (m_target->find(text)) {
        QTextCursor c = m_target->textCursor();
        c.insertText(replacement);
        m_target->setTextCursor(c);
        ++count;
    }
    m_statusLabel->setText(count > 0 ? QString("%1 replaced").arg(count) : "no matches");
}
