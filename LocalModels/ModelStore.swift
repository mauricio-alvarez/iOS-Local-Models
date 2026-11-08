import Foundation
import CryptoKit
import LocalInference

struct CatalogModel: Identifiable {
    let id: String
    let name: String
    let detail: String
    let repository: String
    let revision: String
    let filename: String
    let bytes: Int64
    let sha256: String
    let license: String
    var page: URL { URL(string: "https://huggingface.co/\(repository)")! }
    var url: URL { URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(filename)")! }
    static let all = [
        CatalogModel(id: "gemma", name: "Gemma 3 · 270M", detail: "A small starting point for short prompts and extraction. Q8_0.", repository: "ggml-org/gemma-3-270m-it-GGUF", revision: "e7647be17ae1108f2f605ed061ca0608b171afff", filename: "gemma-3-270m-it-Q8_0.gguf", bytes: 291545600, sha256: "0ef57d2c838458a1952664260dcba38e5bdda37494f3af732f06e4add24068e3", license: "Gemma terms"),
        CatalogModel(id: "qwen", name: "Qwen 3.5 · 0.8B", detail: "More capable text generation. Q4_K_M. Text only in this app.", repository: "axteam/Qwen3.5-0.8B-GGUF", revision: "09ad5aaffcab6b7575c030f347beb2635f26cc7d", filename: "Qwen3.5-0.8B-Q4_K_M.gguf", bytes: 541903360, sha256: "b4e71cb32694733ba40c69e595a0524dfbc2cabe3c28fb7fef99eed4cf8730bf", license: "Apache 2.0")
    ]
}

struct LocalModel: Identifiable, Equatable {
    let url: URL
    let bytes: Int64
    var id: String { url.lastPathComponent }
    var name: String { CatalogModel.all.first { $0.filename == id }?.name ?? url.deletingPathExtension().lastPathComponent }
}

enum Storage {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Models", isDirectory: true)
    }
    static func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }
    static func scan() throws -> [LocalModel] {
        try prepare()
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .map { LocalModel(url: $0, bytes: Int64(try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)) }
            .sorted { $0.name < $1.name }
    }
    static func install(_ source: URL, filename: String, checksum: String? = nil) throws {
        try prepare()
        try ModelFile.validate(source)
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let free = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard free > Int64(size) + 100_000_000 else { throw StoreError.diskFull }
        if let checksum {
            let handle = try FileHandle(forReadingFrom: source)
            defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                hash.update(data: chunk)
            }
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == checksum else { throw StoreError.checksum }
        }
        try Task.checkCancellation()
        let target = directory.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        let staging = directory.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: target)
    }
}

enum StoreError: LocalizedError {
    case diskFull, checksum, network
    var errorDescription: String? {
        switch self {
        case .diskFull: "Free up some storage before importing this model."
        case .checksum: "The downloaded file failed verification. Please download it again."
        case .network: "The model server returned an error. Please try again."
        }
    }
}

final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let update: @Sendable (Double) -> Void
    init(update: @escaping @Sendable (Double) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { update(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
}
