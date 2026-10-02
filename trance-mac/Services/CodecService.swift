import Foundation
import CryptoKit

actor CodecService {
    static let shared = CodecService()
    private var conversions: [String:Task<URL,Error>] = [:]
    func compatibleURL(_ source: URL) async throws -> URL {
        let ext = source.pathExtension.lowercased()
        guard ["webm","ogg"].contains(ext) else { return source }
        let key = source.path
        if let task = conversions[key] { return try await task.value }
        let task = Task { try convert(source) }
        conversions[key] = task
        do { return try await task.value } catch { conversions[key] = nil; throw error }
    }
    private func convert(_ source: URL) throws -> URL {
        let candidates = ["/opt/homebrew/bin/ffmpeg","/usr/local/bin/ffmpeg"]
        guard let executable = candidates.first(where:FileManager.default.isExecutableFile(atPath:)) else { throw TranceError("WebM/Ogg playback requires the approved FFmpeg helper at /opt/homebrew/bin/ffmpeg or /usr/local/bin/ffmpeg") }
        let attributes = try FileManager.default.attributesOfItem(atPath:source.path)
        let stamp = "\(source.path)|\(attributes[.modificationDate] ?? "")|\(attributes[.size] ?? "")"
        let hash = SHA256.hash(data:Data(stamp.utf8)).map { String(format:"%02x",$0) }.joined()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trance-codecs",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let video = source.pathExtension.lowercased() == "webm"
        let destination = directory.appendingPathComponent(hash).appendingPathExtension(video ? "mov":"wav")
        if FileManager.default.fileExists(atPath:destination.path) { return destination }
        let process = Process(); process.executableURL = URL(fileURLWithPath:executable)
        var arguments = ["-nostdin","-v","error","-y","-i",source.path]
        arguments += video ? ["-an","-c:v","prores_ks","-profile:v","2"] : ["-vn","-c:a","pcm_s16le"]
        arguments.append(destination.path); process.arguments = arguments
        let errors = Pipe(); process.standardError = errors; process.standardOutput = FileHandle.nullDevice
        try process.run()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw TranceError("FFmpeg: "+String(decoding:errorData,as:UTF8.self)) }
        return destination
    }
}
