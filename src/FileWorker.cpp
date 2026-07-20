#include "FileWorker.h"

#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QTextStream>

namespace {
constexpr qint64 kChunkSize = 512 * 1024;
}

FileLoadWorker::FileLoadWorker(QString path, QObject *parent)
    : QThread(parent), m_path(std::move(path)) {}

void FileLoadWorker::abort() { m_abort = true; }

void FileLoadWorker::run() {
    const QFileInfo info(m_path);
    if (info.isDir()) {
        emit failed(QString("\"%1\" is a directory, not a file.").arg(info.fileName()));
        return;
    }
    if (info.exists() && !info.isReadable()) {
        emit failed(QString("You don't have permission to read \"%1\".").arg(info.fileName()));
        return;
    }

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
    const QFileInfo info(m_path);
    if (info.exists() && !info.isWritable()) {
        emit failed(QString("You don't have permission to write \"%1\".").arg(info.fileName()));
        return;
    }

    // QSaveFile writes to a sibling temp file and only replaces the real
    // target via an atomic rename once every byte is confirmed flushed to
    // disk. A crash, power loss, or full disk mid-write leaves the
    // original file untouched instead of a half-written/corrupt one.
    QSaveFile file(m_path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit failed(file.errorString());
        return;
    }

    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);
    out << m_text;
    out.flush();

    if (out.status() != QTextStream::Ok) {
        file.cancelWriting();
        emit failed("An error occurred while writing the file contents.");
        return;
    }

    if (!file.commit()) {
        emit failed(file.errorString());
        return;
    }

    emit finishedSaving();
}
