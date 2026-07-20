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

    // Tracks the same glass-opacity slider as the editor/gutter/top bar --
    // was never actually wired up, so the tab strip stayed a fixed opacity.
    void setBackgroundAlpha(int alpha);

signals:
    void tabActivated(int index);
    void tabCloseRequested(int index);
    void newTabRequested();

private:
    QHBoxLayout *m_layout;
    QVector<TabItem *> m_items;
    int m_activeIndex = -1;
};
