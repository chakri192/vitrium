#include "FileWorker.h"

#include <QFile>
#include <QTextStream>

namespace {
constexpr qint64 kChunkSize = 512 * 1024;
}

FileLoadWorker::FileLoadWorker(QString path, QObject *parent)
    : QThread(parent), m_path(std::move(path)) {}

void FileLoadWorker::abort() { m_abort = true; }

void FileLoadWorker::run() {
    QFile file(m_path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit failed(file.errorString());
        return;
    }
    QTextStream in(&file);
    in.setEncoding(QStringConverter::Utf8);
    while (!in.atEnd() && !m_abort) {
        const QString chunk = in.read(kChunkSize);
        if (chunk.isEmpty()) break;
        emit chunkReady(chunk);
    }
    if (!m_abort) emit finishedLoading();
}

FileSaveWorker::FileSaveWorker(QString path, QString text, QObject *parent)
    : QThread(parent), m_path(std::move(path)), m_text(std::move(text)) {}

void FileSaveWorker::run() {
    QFile file(m_path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit failed(file.errorString());
        return;
    }
    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);
    out << m_text;
    if (out.status() != QTextStream::Ok) {
        emit failed("write error");
        return;
    }
    emit finishedSaving();
}
