#pragma once

#include <QThread>
#include <QString>

class FileLoadWorker : public QThread {
    Q_OBJECT

public:
    explicit FileLoadWorker(QString path, QObject *parent = nullptr);
    void abort();

signals:
    void chunkReady(const QString &chunk);
    void finishedLoading();
    void failed(const QString &message);

protected:
    void run() override;

private:
    QString m_path;
    volatile bool m_abort = false;
};

class FileSaveWorker : public QThread {
    Q_OBJECT

public:
    FileSaveWorker(QString path, QString text, QObject *parent = nullptr);

signals:
    void finishedSaving();
    void failed(const QString &message);

protected:
    void run() override;

private:
    QString m_path;
    QString m_text;
};
