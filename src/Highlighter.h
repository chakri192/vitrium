#pragma once

#include <QSyntaxHighlighter>
#include <QRegularExpression>
#include <QTextCharFormat>
#include <QVector>
#include <QString>

class QTextDocument;

class Highlighter : public QSyntaxHighlighter {
    Q_OBJECT

public:
    explicit Highlighter(QTextDocument *document);

    void setLanguageForPath(const QString &path);
    void setLanguage(const QString &language);
    QString language() const { return m_language; }

    // Line-comment prefix for the given language, or empty if that language
    // has no single-line comment syntax (JSON, plain text). Static because
    // callers (comment-toggle) may need it without an existing instance.
    static QString lineCommentPrefix(const QString &language);

protected:
    void highlightBlock(const QString &text) override;

private:
    struct Rule {
        QRegularExpression pattern;
        QTextCharFormat format;
    };

    QString m_language;
    QVector<Rule> m_rules;
    QRegularExpression m_commentStart;
    QRegularExpression m_commentEnd;
    bool m_hasBlockComments = false;
};
