#include "Highlighter.h"

#include <QColor>
#include <QFont>

namespace {

// Phosphor-green / amber / violet terminal palette.
const QColor kKeyword(185, 156, 255);   // soft violet
const QColor kString(140, 255, 160);    // phosphor green
const QColor kComment(90, 107, 98);     // muted moss
const QColor kNumber(255, 176, 103);    // warm amber
const QColor kFunc(110, 231, 183);      // teal-green
const QColor kType(255, 225, 86);       // neon yellow

QTextCharFormat fmt(const QColor &color, bool bold = false, bool italic = false) {
    QTextCharFormat f;
    f.setForeground(color);
    if (bold) f.setFontWeight(QFont::Bold);
    if (italic) f.setFontItalic(true);
    return f;
}

const QStringList kPyKeywords = {
    "and", "as", "assert", "async", "await", "break", "class", "continue",
    "def", "del", "elif", "else", "except", "finally", "for", "from",
    "global", "if", "import", "in", "is", "lambda", "nonlocal", "not",
    "or", "pass", "raise", "return", "try", "while", "with", "yield",
    "None", "True", "False", "self",
};

const QStringList kCKeywords = {
    "auto", "break", "case", "char", "const", "continue", "default", "do",
    "double", "else", "enum", "extern", "float", "for", "goto", "if",
    "inline", "int", "long", "register", "restrict", "return", "short",
    "signed", "sizeof", "static", "struct", "switch", "typedef", "union",
    "unsigned", "void", "volatile", "while", "include", "define", "ifndef",
    "ifdef", "endif", "pragma",
};

const QStringList kJsonKeywords = {"true", "false", "null"};

const QStringList kJsKeywords = {
    "async", "await", "break", "case", "catch", "class", "const", "continue",
    "debugger", "default", "delete", "do", "else", "export", "extends",
    "finally", "for", "function", "if", "import", "in", "instanceof", "let",
    "new", "of", "return", "static", "super", "switch", "this", "throw",
    "try", "typeof", "var", "void", "while", "yield", "true", "false",
    "null", "undefined", "interface", "type", "enum", "implements", "as",
};

const QStringList kShellKeywords = {
    "if", "then", "else", "elif", "fi", "for", "while", "until", "do",
    "done", "case", "esac", "function", "return", "local", "export",
    "readonly", "shift", "break", "continue", "in", "select", "time",
};

}  // namespace

QString Highlighter::lineCommentPrefix(const QString &language) {
    if (language == "python" || language == "shell" || language == "yaml") return "#";
    if (language == "c" || language == "javascript") return "//";
    return QString();  // json, markdown, plain -- no single-line comment syntax
}

Highlighter::Highlighter(QTextDocument *document) : QSyntaxHighlighter(document) {
    setLanguage("plain");
}

void Highlighter::setLanguageForPath(const QString &path) {
    static const QHash<QString, QString> extToLang = {
        {"py", "python"},
        {"c", "c"}, {"h", "c"}, {"cpp", "c"}, {"hpp", "c"}, {"cc", "c"},
        {"js", "javascript"}, {"jsx", "javascript"}, {"ts", "javascript"}, {"tsx", "javascript"}, {"mjs", "javascript"},
        {"sh", "shell"}, {"bash", "shell"}, {"zsh", "shell"},
        {"yaml", "yaml"}, {"yml", "yaml"},
        {"json", "json"},
        {"md", "markdown"},
        {"txt", "plain"},
    };
    const int dot = path.lastIndexOf('.');
    const QString ext = dot >= 0 ? path.mid(dot + 1).toLower() : QString();
    setLanguage(extToLang.value(ext, "plain"));
}

void Highlighter::setLanguage(const QString &language) {
    m_language = language;
    m_rules.clear();
    m_hasBlockComments = false;

    const QTextCharFormat stringFmt = fmt(kString);
    const QTextCharFormat commentFmt = fmt(kComment, false, true);
    const QTextCharFormat numberFmt = fmt(kNumber);
    const QTextCharFormat keywordFmt = fmt(kKeyword, true);
    const QTextCharFormat funcFmt = fmt(kFunc);
    const QTextCharFormat typeFmt = fmt(kType);

    if (language == "python") {
        for (const auto &kw : kPyKeywords)
            m_rules.append({QRegularExpression("\\b" + kw + "\\b"), keywordFmt});
        m_rules.append({QRegularExpression(R"("[^"\\]*(\\.[^"\\]*)*")"), stringFmt});
        m_rules.append({QRegularExpression(R"('[^'\\]*(\\.[^'\\]*)*')"), stringFmt});
        m_rules.append({QRegularExpression("#[^\n]*"), commentFmt});
        m_rules.append({QRegularExpression(R"(\b[A-Za-z_][A-Za-z0-9_]*(?=\())"), funcFmt});
        m_rules.append({QRegularExpression(R"(\b\d+(\.\d+)?\b)"), numberFmt});
    } else if (language == "c") {
        for (const auto &kw : kCKeywords)
            m_rules.append({QRegularExpression("\\b" + kw + "\\b"), keywordFmt});
        m_rules.append({QRegularExpression(R"("[^"\\]*(\\.[^"\\]*)*")"), stringFmt});
        m_rules.append({QRegularExpression("//[^\n]*"), commentFmt});
        m_rules.append({QRegularExpression(R"(\b[A-Za-z_][A-Za-z0-9_]*(?=\())"), funcFmt});
        m_rules.append({QRegularExpression(R"(\b\d+(\.\d+)?[fFuUlL]?\b)"), numberFmt});
        m_rules.append({QRegularExpression(R"(\b[A-Z][A-Za-z0-9_]*\b)"), typeFmt});
        m_commentStart = QRegularExpression(R"(/\*)");
        m_commentEnd = QRegularExpression(R"(\*/)");
        m_hasBlockComments = true;
    } else if (language == "javascript") {
        for (const auto &kw : kJsKeywords)
            m_rules.append({QRegularExpression("\\b" + kw + "\\b"), keywordFmt});
        m_rules.append({QRegularExpression(R"("[^"\\]*(\\.[^"\\]*)*")"), stringFmt});
        m_rules.append({QRegularExpression(R"('[^'\\]*(\\.[^'\\]*)*')"), stringFmt});
        m_rules.append({QRegularExpression("`[^`]*`"), stringFmt});
        m_rules.append({QRegularExpression("//[^\n]*"), commentFmt});
        m_rules.append({QRegularExpression(R"(\b[A-Za-z_$][A-Za-z0-9_$]*(?=\())"), funcFmt});
        m_rules.append({QRegularExpression(R"(\b\d+(\.\d+)?\b)"), numberFmt});
        m_commentStart = QRegularExpression(R"(/\*)");
        m_commentEnd = QRegularExpression(R"(\*/)");
        m_hasBlockComments = true;
    } else if (language == "shell") {
        for (const auto &kw : kShellKeywords)
            m_rules.append({QRegularExpression("\\b" + kw + "\\b"), keywordFmt});
        m_rules.append({QRegularExpression(R"("[^"\\]*(\\.[^"\\]*)*")"), stringFmt});
        m_rules.append({QRegularExpression(R"('[^']*')"), stringFmt});
        m_rules.append({QRegularExpression("#[^\n]*"), commentFmt});
        m_rules.append({QRegularExpression(R"(\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^}]+\})"), typeFmt});
        m_rules.append({QRegularExpression(R"(\b[A-Za-z_][A-Za-z0-9_]*(?=\())"), funcFmt});
    } else if (language == "yaml") {
        m_rules.append({QRegularExpression("^[^:#\n]+(?=:)"), typeFmt});
        m_rules.append({QRegularExpression(R"("[^"\\]*(\\.[^"\\]*)*")"), stringFmt});
        m_rules.append({QRegularExpression(R"('[^']*')"), stringFmt});
        m_rules.append({QRegularExpression("#[^\n]*"), commentFmt});
        m_rules.append({QRegularExpression(R"(\b(true|false|null|~)\b)"), keywordFmt});
        m_rules.append({QRegularExpression(R"(\b-?\d+(\.\d+)?\b)"), numberFmt});
        m_rules.append({QRegularExpression("^\\s*-"), funcFmt});
    } else if (language == "json") {
        for (const auto &kw : kJsonKeywords)
            m_rules.append({QRegularExpression("\\b" + kw + "\\b"), keywordFmt});
        m_rules.append({QRegularExpression(R"("[^"\\]*(\\.[^"\\]*)*"\s*(?=:))"), typeFmt});
        m_rules.append({QRegularExpression(R"("[^"\\]*(\\.[^"\\]*)*")"), stringFmt});
        m_rules.append({QRegularExpression(R"(\b-?\d+(\.\d+)?\b)"), numberFmt});
    } else if (language == "markdown") {
        m_rules.append({QRegularExpression("^#{1,6}\\s.*$"), fmt(kKeyword, true)});
        m_rules.append({QRegularExpression(R"(\*\*[^*]+\*\*)"), fmt(kType, true)});
        m_rules.append({QRegularExpression(R"(\*[^*]+\*)"), fmt(kString, false, true)});
        m_rules.append({QRegularExpression("`[^`]+`"), funcFmt});
    }

    rehighlight();
}

void Highlighter::highlightBlock(const QString &text) {
    for (const auto &rule : m_rules) {
        auto it = rule.pattern.globalMatch(text);
        while (it.hasNext()) {
            const auto match = it.next();
            setFormat(match.capturedStart(), match.capturedLength(), rule.format);
        }
    }

    if (!m_hasBlockComments) return;

    setCurrentBlockState(0);
    int startIndex = 0;
    if (previousBlockState() != 1) {
        const auto m = m_commentStart.match(text);
        startIndex = m.hasMatch() ? m.capturedStart() : -1;
    }

    while (startIndex >= 0) {
        const auto endMatch = m_commentEnd.match(text, startIndex);
        if (endMatch.hasMatch()) {
            const int endIndex = endMatch.capturedEnd();
            setFormat(startIndex, endIndex - startIndex, fmt(kComment, false, true));
            const auto nextMatch = m_commentStart.match(text, endIndex);
            startIndex = nextMatch.hasMatch() ? nextMatch.capturedStart() : -1;
        } else {
            setFormat(startIndex, text.length() - startIndex, fmt(kComment, false, true));
            setCurrentBlockState(1);
            startIndex = -1;
        }
    }
}
