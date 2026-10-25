// The Heat Detector (contract §6): FluidInference's CoreML build of Laya, installed on this Mac when you press Download.
// Pinned to one revision, and every file is checked by size and SHA-256 before it counts.
import CryptoKit
import Foundation

public enum HeatDetector {
    public struct File: Sendable {
        public let path: String
        public let size: Int64
        public let sha256: String
        public init(_ path: String, _ size: Int64, _ sha256: String) { self.path = path; self.size = size; self.sha256 = sha256 }
    }

    public enum Failure: LocalizedError {
        case http(Int, String), badFile(String)
        public var errorDescription: String? {
            switch self {
            case .http(let status, let path): "The download of \(path) failed (\(status))."
            case .badFile(let path): "\(path) didn't match its checksum, so it wasn't used."
            }
        }
    }

    public static let revision = "7b8d7a2b7e28e746c6ecaad44bbcd5cf251a4fcc"
    /// The model's page, so you can see what you're downloading.
    public static let page = URL(string: "https://huggingface.co/FluidInference/laya-coreml")!
    public static var baseURL: URL { URL(string: "https://huggingface.co/FluidInference/laya-coreml/resolve/\(revision)/")! }
    static let bucket = "laya_multilingual_e8_L128_options32.mlmodelc/"
    public static let files: [File] = [
        File("tokenizer.json", 34_363_188, "609d8f4c067cd3950f88594c5a802616cea245823836ef5848ee4fc40aab5b6f"),
        File(bucket + "analytics/coremldata.bin", 243, "5cabcada4e3adc09e026c4b37a48d71e828bb3f80d12de0356b3369375ba1da6"),
        File(bucket + "coremldata.bin", 1_115, "4fb10774cd0860881220a37c80b416f465e3a9b5636f83c740647bafc14fbce5"),
        File(bucket + "model.mil", 384_857, "bcdb6102dacea9581875b3e8bc0f05e0b568d437bc20a8cf35b11f06edfa919a"),
        File(bucket + "weights/weight.bin", 448_093_696, "ca1e5da71f1498eac7b68722c9f5c3d43d1ce299aaf0c29743585749f3cc9677"),
    ]
    public static var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    /// ~/Library/Application Support/Lunte/laya-coreml, next to the log.
    public static var dir: URL { EventLog.defaultURL.deletingLastPathComponent().appendingPathComponent("laya-coreml") }

    /// Every file is there with the right size. Checksums are checked once, as each file arrives.
    public static func isInstalled(in dir: URL = dir, files: [File] = files) -> Bool {
        files.allSatisfy { size(of: dir.appendingPathComponent($0.path)) == $0.size }
    }

    /// Downloads whatever is missing into `dir`. Each file lands next to its place as `.part`, and only moves in once
    /// its size and SHA-256 match. `progress` gets the share done, 0...1, across all files.
    public static func install(into dir: URL = dir, files: [File] = files, from base: URL = baseURL,
                               progress: @escaping @Sendable (Double) -> Void) async throws {
        let total = Double(files.reduce(0) { $0 + $1.size })
        var done: Int64 = 0
        for file in files {
            let target = dir.appendingPathComponent(file.path)
            if size(of: target) == file.size { done += file.size; continue }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let part = target.appendingPathExtension("part")
            let before = done
            try await Download.fetch(base.appendingPathComponent(file.path), to: part, path: file.path) { written in
                progress(min(1, Double(before + written) / total))
            }
            guard size(of: part) == file.size, try sha256(of: part) == file.sha256 else {
                try? FileManager.default.removeItem(at: part)
                throw Failure.badFile(file.path)
            }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: part, to: target)
            done += file.size
            progress(Double(done) / total)
        }
    }

    static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
    }

    /// Reads the file in 8 MB chunks, so a 450 MB file never sits in memory at once.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// One file over URLSession, reporting bytes as they arrive (the async `download(from:)` has no progress).
private final class Download: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL, path: String, onBytes: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?

    private init(_ destination: URL, _ path: String, _ onBytes: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination; self.path = path; self.onBytes = onBytes
    }

    static func fetch(_ url: URL, to destination: URL, path: String, onBytes: @escaping @Sendable (Int64) -> Void) async throws {
        let d = Download(destination, path, onBytes)
        let session = URLSession(configuration: .default, delegate: d, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            d.continuation = c
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite _: Int64) {
        onBytes(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            moveError = HeatDetector.Failure.http(http.statusCode, path)
            return
        }
        do { // the temporary file is gone once this returns, so it moves now
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch { moveError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let failure = error ?? moveError { continuation?.resume(throwing: failure) } else { continuation?.resume() }
        continuation = nil
    }
}
