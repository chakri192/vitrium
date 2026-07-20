#pragma once

#include <QWidget>
#include <QPropertyAnimation>
#include <QVariantAnimation>
#include <QGraphicsOpacityEffect>

class QSlider;
class QMainWindow;
class QMouseEvent;

class TrafficDot : public QWidget {
    Q_OBJECT
public:
    TrafficDot(const QString &color, const QString &hoverColor, QWidget *parent = nullptr);

signals:
    void clicked();

protected:
    void mousePressEvent(QMouseEvent *event) override;
};

class AutoHideBar : public QWidget {
    Q_OBJECT

public:
    explicit AutoHideBar(QMainWindow *window);

    QSlider *opacitySlider() const { return m_opacitySlider; }
    bool isRevealed() const { return m_visible; }

    void reveal();
    void conceal();

    // Tracks the same glass-opacity slider as the editor and gutter -- this
    // was never actually wired up before now, which is why the top bar
    // stayed at a fixed opacity regardless of the slider.
    void setBackgroundAlpha(int alpha);

signals:
    void openRequested();
    void saveRequested();
    void saveAsRequested();
    void closeRequested();
    void minimizeRequested();
    void maximizeRequested();

protected:
    void mousePressEvent(QMouseEvent *event) override;

private:
    void buildContents();

    QMainWindow *m_window;
    QGraphicsOpacityEffect *m_opacityFx;
    QPropertyAnimation *m_fade;
    QVariantAnimation *m_heightAnim;
    QSlider *m_opacitySlider;
    bool m_visible = false;
};
