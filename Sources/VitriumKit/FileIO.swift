import AppKit

enum FileIOError: LocalizedError {
    case tooLarge(bytes: Int)
    case notText

    var errorDescription: String? {
        switch self {
        case .tooLarge(let bytes):
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return "That file is \(size). Vitrium opens files up to \(ByteCountFormatter.string(fromByteCount: Int64(FileIO.maxFileSize), countStyle: .file))."
        case .notText:
            return "That file doesn't look like text — it contains null bytes."
        }
    }
}

enum FileIO {

    static let maxFileSize = 64 * 1024 * 1024

    struct Loaded {
        let text: String
        let modificationDate: Date?
    }

    /// Reads off the main thread and hands the result back on it. The read is a
    /// single `Data(contentsOf:)` rather than the old chunked worker — for the
    /// file sizes this editor accepts, the chunking bought nothing but a queue
    /// to get wrong.
    static func load(url: URL, completion: @escaping (Result<Loaded, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Loaded, Error>
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attributes[.size] as? Int) ?? 0
                guard size <= maxFileSize else { throw FileIOError.tooLarge(bytes: size) }

                let data = try Data(contentsOf: url)
                guard !data.contains(0) else { throw FileIOError.notText }

                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                result = .success(Loaded(text: text, modificationDate: attributes[.modificationDate] as? Date))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Writes atomically: the bytes land in a sibling temp file and only replace
    /// the target once the write is complete, so a crash mid-save leaves the
    /// original intact rather than truncated.
    @discardableResult
    static func save(text: String, to url: URL) throws -> Date? {
        let data = Data(text.utf8)
        try data.write(to: url, options: .atomic)
        return try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    static func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
