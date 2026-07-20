#pragma once

#include <QWidget>
#include <QTextDocument>

class QLineEdit;
class QLabel;
class QPlainTextEdit;
class QPushButton;
class QCheckBox;
class QKeyEvent;

// Self-contained find/replace overlay: owns its own search logic against a
// target QPlainTextEdit rather than routing everything back through
// MainWindow with signals -- there's no reason for the caller to know how
// find/replace works internally.
class FindBar : public QWidget {
    Q_OBJECT

public:
    explicit FindBar(QPlainTextEdit *target, QWidget *parent = nullptr);

    void openFind();
    void openReplace();
    void closeBar();

protected:
    void keyPressEvent(QKeyEvent *event) override;

private slots:
    void findNext();
    void findPrev();
    void doReplace();
    void doReplaceAll();
    void toggleReplaceRow();
    void onQueryChanged();

private:
    void updateStatus(bool found);
    void updateMatchCount();
    void buildContents();
    QTextDocument::FindFlags currentFlags(bool backward) const;

    QPlainTextEdit *m_target;
    QLineEdit *m_searchField;
    QLineEdit *m_replaceField;
    QWidget *m_replaceRow;
    QLabel *m_statusLabel;
    QPushButton *m_replaceToggleBtn;
    QCheckBox *m_caseSensitiveBox;
    QCheckBox *m_wholeWordBox;
};
