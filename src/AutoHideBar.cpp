#include "AutoHideBar.h"
#include "Editor.h"  // kAccent
#include "Theme.h"

#include <QMainWindow>
#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QSlider>
#include <QMouseEvent>
#include <QWindow>
#include <QCursor>

TrafficDot::TrafficDot(const QString &color, const QString &hoverColor, QWidget *parent)
    : QWidget(parent) {
    setFixedSize(12, 12);
    setCursor(Qt::PointingHandCursor);
    setStyleSheet(QString(
        "TrafficDot { background: %1; border-radius: 6px; }").arg(color));
    setAttribute(Qt::WA_StyledBackground, true);
    setProperty("baseColor", color);
    setProperty("hoverColor", hoverColor);
}

void TrafficDot::mousePressEvent(QMouseEvent *event) {
    if (event->button() == Qt::LeftButton) emit clicked();
}

AutoHideBar::AutoHideBar(QMainWindow *window) : QWidget(nullptr), m_window(window) {
    setMinimumHeight(0);
    setMaximumHeight(0);
    setFixedHeight(0);  // starts collapsed; reveal()/conceal() animate this
    setStyleSheet(QString(
        "background: rgba(9, 11, 12, 235); border-bottom: 1px solid rgba(%1, %2, %3, 60);")
        .arg(kAccent.red()).arg(kAccent.green()).arg(kAccent.blue()));

    m_opacityFx = new QGraphicsOpacityEffect(this);
    m_opacityFx->setOpacity(0.0);
    setGraphicsEffect(m_opacityFx);

    m_fade = new QPropertyAnimation(m_opacityFx, "opacity", this);
    m_fade->setDuration(160);
    m_fade->setEasingCurve(QEasingCurve::OutCubic);

    // QVariantAnimation instead of a QPropertyAnimation on maximumHeight --
    // maximumHeight is only an upper bound, it doesn't force the layout to
    // actually grow the widget past its natural content size, which is why
    // an earlier version of this plateaued short of the target height.
    // setFixedHeight() forces min == max == exactly this value every frame.
    m_heightAnim = new QVariantAnimation(this);
    m_heightAnim->setDuration(160);
    m_heightAnim->setEasingCurve(QEasingCurve::OutCubic);
    connect(m_heightAnim, &QVariantAnimation::valueChanged, this, [this](const QVariant &v) {
        setFixedHeight(v.toInt());
    });

    buildContents();
}

void AutoHideBar::buildContents() {
    auto *layout = new QHBoxLayout(this);
    layout->setContentsMargins(14, 0, 14, 0);
    layout->setSpacing(10);

    auto *closeDot = new TrafficDot("#FF5F57", "#FF8078", this);
    connect(closeDot, &TrafficDot::clicked, this, &AutoHideBar::closeRequested);
    auto *minDot = new TrafficDot("#FEBC2E", "#FFD066", this);
    connect(minDot, &TrafficDot::clicked, this, &AutoHideBar::minimizeRequested);
    auto *zoomDot = new TrafficDot("#28C840", "#5CDE72", this);
    connect(zoomDot, &TrafficDot::clicked, this, &AutoHideBar::maximizeRequested);
    layout->addWidget(closeDot);
    layout->addWidget(minDot);
    layout->addWidget(zoomDot);

    auto *title = new QLabel("VITRUM", this);
    title->setStyleSheet(QString(
        "color: rgba(%1, %2, %3, 220); font-weight: 600; letter-spacing: 2px; "
        "background: transparent; margin-left: 6px;")
        .arg(kAccent.red()).arg(kAccent.green()).arg(kAccent.blue()));
    layout->addWidget(title);
    layout->addSpacing(18);

    auto addButton = [&](const QString &label, auto signalPtr) {
        auto *btn = new QPushButton(label, this);
        btn->setCursor(Qt::PointingHandCursor);
        btn->setStyleSheet(QString(
            "QPushButton { color: #C9D6CE; background: transparent; border: none; "
            "padding: 4px 8px; font-size: 12px; }"
            "QPushButton:hover { color: rgb(%1, %2, %3); }")
            .arg(kAccent.red()).arg(kAccent.green()).arg(kAccent.blue()));
        connect(btn, &QPushButton::clicked, this, signalPtr);
        layout->addWidget(btn);
    };
    addButton("Open", &AutoHideBar::openRequested);
    addButton("Save", &AutoHideBar::saveRequested);
    addButton("Save As", &AutoHideBar::saveAsRequested);

    layout->addStretch(1);

    auto *opacityLabel = new QLabel("glass", this);
    opacityLabel->setStyleSheet("color: #7C8A82; background: transparent; font-size: 11px;");
    layout->addWidget(opacityLabel);

    m_opacitySlider = new QSlider(Qt::Horizontal, this);
    m_opacitySlider->setMinimum(Theme::kMinAlpha);
    m_opacitySlider->setMaximum(Theme::kMaxAlpha);
    m_opacitySlider->setValue(Theme::kDefaultAlpha);
    m_opacitySlider->setFixedWidth(120);
    m_opacitySlider->setStyleSheet(QString(
        "QSlider::groove:horizontal { height: 3px; background: rgba(255,255,255,30); border-radius: 1px; }"
        "QSlider::handle:horizontal { background: rgb(%1, %2, %3); width: 12px; height: 12px; "
        "margin: -5px 0; border-radius: 6px; }")
        .arg(kAccent.red()).arg(kAccent.green()).arg(kAccent.blue()));
    layout->addWidget(m_opacitySlider);
}

void AutoHideBar::reveal() {
    if (m_visible) return;
    m_visible = true;
    m_fade->stop();
    m_fade->setStartValue(m_opacityFx->opacity());
    m_fade->setEndValue(1.0);
    m_fade->start();
    m_heightAnim->stop();
    m_heightAnim->setStartValue(height());
    m_heightAnim->setEndValue(Theme::kBarHeight);
    m_heightAnim->start();
}

void AutoHideBar::conceal() {
    if (!m_visible) return;
    m_visible = false;
    m_fade->stop();
    m_fade->setStartValue(m_opacityFx->opacity());
    m_fade->setEndValue(0.0);
    m_fade->start();
    m_heightAnim->stop();
    m_heightAnim->setStartValue(height());
    m_heightAnim->setEndValue(0);
    m_heightAnim->start();
}

void AutoHideBar::mousePressEvent(QMouseEvent *event) {
    if (event->button() == Qt::LeftButton) {
        if (QWindow *handle = m_window->windowHandle()) {
            handle->startSystemMove();
            event->accept();
            return;
        }
    }
    QWidget::mousePressEvent(event);
}
