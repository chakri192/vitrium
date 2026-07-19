#pragma once

#include <QWidget>
#include <QVector>

class QHBoxLayout;
class TabItem;

class TabBar : public QWidget {
    Q_OBJECT

public:
    explicit TabBar(QWidget *parent = nullptr);

    int addTab(const QString &label);
    void setTabLabel(int index, const QString &label);
    void setTabDirty(int index, bool dirty);
    void setActiveTab(int index);
    void removeTab(int index);
    int count() const { return m_items.size(); }

signals:
    void tabActivated(int index);
    void tabCloseRequested(int index);
    void newTabRequested();

private:
    QHBoxLayout *m_layout;
    QVector<TabItem *> m_items;
    int m_activeIndex = -1;
};
