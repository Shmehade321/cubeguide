import Foundation

public enum ResourceError: Error { case missingResource(String), invalidManifest, corruptTable(String) }

package struct SolverTables: Sendable {
    package let version: String
    private let ordered: [[UInt16]]
    fileprivate init(version: String, ordered: [[UInt16]]) { self.version=version;self.ordered=ordered }
    package subscript(_ id: TableID) -> [UInt16] { ordered[Int(id.rawValue)-1] }
}

private struct ResourceManifest: Decodable {
    let formatVersion: Int, generatorVersion: String, sourceCommit: String
    let tables: [Record]
    struct Record: Decodable {
        let identifier: UInt32, filename: String, rows: Int, columns: Int, elementWidth: Int, byteCount: Int, sha256: String
    }
}

package enum SolverResources {
    package static func bundledDirectory() throws -> URL {
        guard let root = Bundle.module.resourceURL else { throw ResourceError.missingResource("Tables") }
        return root.appendingPathComponent("Tables",isDirectory:true)
    }

    package static func loadBundled(checkCancellation: () throws -> Void = {}) throws -> SolverTables {
        try load(from:bundledDirectory(),checkCancellation:checkCancellation)
    }

    package static func load(from directory: URL, checkCancellation: () throws -> Void = {}) throws -> SolverTables {
        try checkCancellation()
        let manifestData = try read(directory.appendingPathComponent("manifest.json"),limit:65536)
        let manifest: ResourceManifest
        do { manifest = try JSONDecoder().decode(ResourceManifest.self,from:manifestData) }
        catch { throw ResourceError.invalidManifest }
        guard manifest.formatVersion == 1, manifest.generatorVersion == "cubeguide-tables-v1",
              isHex(manifest.sourceCommit,length:40), manifest.tables.count == 10,
              Set(manifest.tables.map(\.identifier)) == Set(TableID.allCases.map(\.rawValue)) else {
            throw ResourceError.invalidManifest
        }
        try checkCancellation()
        var ordered: [[UInt16]] = []
        for id in TableID.allCases {
            guard let record = manifest.tables.first(where: {$0.identifier == id.rawValue}),
                  record.filename == id.filename, record.rows == id.rows, record.columns == id.columns,
                  record.elementWidth == id.width, record.byteCount == id.byteCount, isHex(record.sha256,length:64) else {
                throw ResourceError.invalidManifest
            }
            try checkCancellation()
            let data = try read(directory.appendingPathComponent(id.filename),limit:id.byteCount)
            do { ordered.append(try TableCodec.decode(data,id:id,sha256:record.sha256).values) }
            catch { throw ResourceError.corruptTable(id.filename) }
            try checkCancellation()
        }
        return SolverTables(version:TableCodec.digest(manifestData),ordered:ordered)
    }

    private static func isHex(_ value: String, length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func read(_ url: URL, limit: Int) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom:url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount:limit+1) ?? Data()
            guard data.count <= limit else { throw ResourceError.corruptTable(url.lastPathComponent) }
            return data
        } catch let error as ResourceError { throw error }
        catch { throw ResourceError.missingResource(url.lastPathComponent) }
    }
}
