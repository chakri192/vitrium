#include "TabBar.h"
#include "Editor.h"  // kAccent
#include "Theme.h"

#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QMouseEvent>
#include <QCursor>

// Internal, not exposed via the header -- one strip item: label + dirty dot
// + close button, with its own active/inactive visual state.
class TabItem : public QWidget {
    Q_OBJECT

public:
    explicit TabItem(const QString &label, QWidget *parent = nullptr)
        : QWidget(parent) {
        setFixedHeight(Theme::kTabHeight);
        setCursor(Qt::PointingHandCursor);
        setAttribute(Qt::WA_StyledBackground, true);

        auto *layout = new QHBoxLayout(this);
        layout->setContentsMargins(12, 0, 8, 0);
        layout->setSpacing(6);

        m_dot = new QLabel(this);
        m_dot->setFixedSize(6, 6);
        m_dot->hide();
        layout->addWidget(m_dot);

        m_label = new QLabel(label, this);
        m_label->setStyleSheet("background: transparent;");
        layout->addWidget(m_label);

        m_closeBtn = new QPushButton("\u2715", this);
        m_closeBtn->setFixedSize(16, 16);
        m_closeBtn->setCursor(Qt::PointingHandCursor);
        m_closeBtn->setStyleSheet(
            "QPushButton { color: #6E8A79; background: transparent; border: none; font-size: 10px; }"
            "QPushButton:hover { color: #F2FAF6; }");
        connect(m_closeBtn, &QPushButton::clicked, this, [this] { emit closeClicked(); });
        layout->addWidget(m_closeBtn);

        setActive(false);
    }

    void setLabel(const QString &text) { m_label->setText(text); }

    void setDirty(bool dirty) {
        m_dot->setVisible(dirty);
        if (dirty) {
            m_dot->setStyleSheet(QString("background: rgb(%1, %2, %3); border-radius: 3px;")
                .arg(kAccent.red()).arg(kAccent.green()).arg(kAccent.blue()));
        }
    }

    void setActive(bool active) {
        m_active = active;
        if (active) {
            setStyleSheet(QString(
                "TabItem { background: rgba(20, 24, 24, 235); "
                "border-bottom: 2px solid rgb(%1, %2, %3); }")
                .arg(kAccent.red()).arg(kAccent.green()).arg(kAccent.blue()));
            m_label->setStyleSheet("color: #F2FAF6; background: transparent; font-size: 12px;");
        } else {
            setStyleSheet(
                "TabItem { background: transparent; border-bottom: 2px solid transparent; }");
            m_label->setStyleSheet("color: #7C8A82; background: transparent; font-size: 12px;");
        }
    }

signals:
    void activated();
    void closeClicked();

protected:
    void mousePressEvent(QMouseEvent *event) override {
        if (event->button() == Qt::LeftButton) emit activated();
    }

private:
    QLabel *m_label;
    QLabel *m_dot;
    QPushButton *m_closeBtn;
    bool m_active = false;
};

#include "TabBar.moc"

TabBar::TabBar(QWidget *parent) : QWidget(parent) {
    setFixedHeight(Theme::kTabHeight);
    setStyleSheet("background: rgba(9, 11, 12, 215);");
    setAttribute(Qt::WA_StyledBackground, true);

    m_layout = new QHBoxLayout(this);
    m_layout->setContentsMargins(0, 0, 0, 0);
    m_layout->setSpacing(0);

    auto *addBtn = new QPushButton("+", this);
    addBtn->setFixedSize(24, 24);
    addBtn->setCursor(Qt::PointingHandCursor);
    addBtn->setStyleSheet(
        "QPushButton { color: #6E8A79; background: transparent; border: none; font-size: 14px; }"
        "QPushButton:hover { color: #F2FAF6; }");
    connect(addBtn, &QPushButton::clicked, this, &TabBar::newTabRequested);
    m_layout->addWidget(addBtn);

    m_layout->addStretch(1);
}

int TabBar::addTab(const QString &label) {
    auto *item = new TabItem(label, this);
    const int index = m_items.size();
    m_items.append(item);
    m_layout->insertWidget(index, item);

    connect(item, &TabItem::activated, this, [this, item] {
        emit tabActivated(m_items.indexOf(item));
    });
    connect(item, &TabItem::closeClicked, this, [this, item] {
        emit tabCloseRequested(m_items.indexOf(item));
    });

    return index;
}

void TabBar::setTabLabel(int index, const QString &label) {
    if (index >= 0 && index < m_items.size()) m_items[index]->setLabel(label);
}

void TabBar::setTabDirty(int index, bool dirty) {
    if (index >= 0 && index < m_items.size()) m_items[index]->setDirty(dirty);
}

void TabBar::setActiveTab(int index) {
    for (int i = 0; i < m_items.size(); ++i) m_items[i]->setActive(i == index);
    m_activeIndex = index;
}

void TabBar::removeTab(int index) {
    if (index < 0 || index >= m_items.size()) return;
    TabItem *item = m_items.takeAt(index);
    m_layout->removeWidget(item);
    item->deleteLater();
}
