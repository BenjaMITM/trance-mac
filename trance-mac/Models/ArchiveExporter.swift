import Foundation

public enum ArchiveExporter {
    public static func export(_ session: Session, to url: URL) throws {
        var paths = Set<String>()
        for pool in session.pools.values { paths.formUnion(pool.images+pool.animations+pool.fonts+pool.audio) }
        for program in session.json["program_map"].object.values { paths.formUnion(program["custom_visual_pattern"].array.map { $0["file"].string }) }
        for item in session.json["playlist"].object.values { paths.formUnion(item["audio_event"].array.filter { $0["type"].string == "play" }.map { $0["path"].string }) }
        var portable = session.json
        portable["theme_scan_root"] = .object(["dir": .string("."),"auto_rescan": .bool(false)])
        for (name,pool) in session.pools {
            portable["theme_map"][name] = .object(["image_path": .array(pool.images.map(JSONValue.string)),"animation_path": .array(pool.animations.map(JSONValue.string)),"font_path": .array(pool.fonts.map(JSONValue.string)),"audio_path": .array(pool.audio.map(JSONValue.string)),"text_line": .array(pool.text.map(JSONValue.string))])
        }
        var entries: [(String,Data)] = [("session.json",try portable.encoded())]
        for path in paths.sorted() where !path.isEmpty { entries.append((path.replacingOccurrences(of:"\\",with:"/"),try Data(contentsOf:session.resolve(path)))) }
        var zip = Data(), central = Data()
        guard entries.count <= Int(UInt16.max) else { throw TranceError("ZIP has too many assets (ZIP64 is required)") }
        for (path,bytes) in entries {
            let name = Data(path.utf8), crc = crc32(bytes)
            guard bytes.count <= Int(UInt32.max), zip.count <= Int(UInt32.max), name.count <= Int(UInt16.max) else { throw TranceError("Archive exceeds ZIP32 size limits") }
            let offset = UInt32(zip.count), size = UInt32(bytes.count)
            zip.appendLE(UInt32(0x04034b50)); zip.appendLE(UInt16(20)); zip.appendLE(UInt16(0x800)); zip.appendLE(UInt16(0)); zip.appendLE(UInt16(0)); zip.appendLE(UInt16(0x21)); zip.appendLE(crc); zip.appendLE(size); zip.appendLE(size); zip.appendLE(UInt16(name.count)); zip.appendLE(UInt16(0)); zip.append(name); zip.append(bytes)
            central.appendLE(UInt32(0x02014b50)); central.appendLE(UInt16(20)); central.appendLE(UInt16(20)); central.appendLE(UInt16(0x800)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0x21)); central.appendLE(crc); central.appendLE(size); central.appendLE(size); central.appendLE(UInt16(name.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0)); central.appendLE(offset); central.append(name)
        }
        guard zip.count+central.count <= Int(UInt32.max) else { throw TranceError("Archive exceeds ZIP32 size limits") }
        let offset = UInt32(zip.count); zip.append(central)
        zip.appendLE(UInt32(0x06054b50)); zip.appendLE(UInt16(0)); zip.appendLE(UInt16(0)); zip.appendLE(UInt16(entries.count)); zip.appendLE(UInt16(entries.count)); zip.appendLE(UInt32(central.count)); zip.appendLE(offset); zip.appendLE(UInt16(0))
        try zip.write(to:url,options:.atomic)
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ ((crc&1) != 0 ? 0xedb88320 : 0) } }
        return crc ^ 0xffffffff
    }
}
private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; Swift.withUnsafeBytes(of:&v) { append(contentsOf:$0) } }
}
