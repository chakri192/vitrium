#include <QApplication>
#include "MainWindow.h"

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    app.setApplicationName("Vitrum");
    // Native macOS/Windows styles quietly ignore the alpha channel on custom
    // palettes for text widgets -- Fusion respects it, so the glass tint
    // actually renders everywhere.
    app.setStyle("Fusion");

    MainWindow window;
    window.show();

    if (argc > 1) window.loadFile(QString::fromLocal8Bit(argv[1]));

    return app.exec();
}
