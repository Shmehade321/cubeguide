import Foundation
import Testing
@testable import CubeSolver3

private func withResourceCopy(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.copyItem(at:try SolverResources.bundledDirectory(),to:directory)
    defer { try? FileManager.default.removeItem(at:directory) }
    try body(directory)
}
private func changeManifest(_ root: URL, _ change: (inout [String:Any]) -> Void) throws {
    let path = root.appendingPathComponent("manifest.json")
    var manifest = try #require(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any])
    change(&manifest)
    try JSONSerialization.data(withJSONObject:manifest).write(to:path)
}

@Test("V04: load all actual bundled tables and retain the verified resource identity")
func bundledTables() throws {
    let tables = try SolverResources.loadBundled()
    #expect(Array(tables[.slicePermMove].prefix(10)) == [0,0,0,0,0,0,21,6,2,1])
    #expect(tables[.twistSliceDistance][494] == 0)
    #expect(tables[.flipSliceDistance][494] == 0)
    #expect(tables.version.count == 64)
    for id in TableID.allCases { #expect(tables[id].count == id.count) }
}

@Test("V04: missing, corrupted and oversized table files are blocked")
func damagedResources() throws {
    try withResourceCopy { directory in
        let file = directory.appendingPathComponent("slicePermMove.bin")
        var data = try Data(contentsOf:file)
        data[36] ^= 1
        try data.write(to:file)
        #expect(throws: ResourceError.self) { try SolverResources.load(from:directory) }
        try FileManager.default.removeItem(at:file)
        #expect(throws: ResourceError.self) { try SolverResources.load(from:directory) }
        try (data+Data([0])).write(to:file)
        #expect(throws: ResourceError.self) { try SolverResources.load(from:directory) }
    }
}

@Test("V04: manifests reject unknown versions, traversal, duplicate records and oversized data")
func invalidManifests() throws {
    for kind in 0..<4 {
        try withResourceCopy { directory in
            try changeManifest(directory) { manifest in
                if kind == 0 { manifest["formatVersion"] = 2 }
                else if kind == 1 { manifest["sourceCommit"] = "invented" }
                else if var records = manifest["tables"] as? [[String:Any]] {
                    if kind == 2 { records[0]["filename"] = "../outside.bin" }
                    else { records[0] = records[1] }
                    manifest["tables"] = records
                }
            }
            #expect(throws: ResourceError.self) { try SolverResources.load(from:directory) }
        }
    }
    try withResourceCopy { directory in
        let file = directory.appendingPathComponent("manifest.json")
        try Data(repeating:65,count:65537).write(to:file)
        #expect(throws: ResourceError.self) { try SolverResources.load(from:directory) }
    }
}

@Test("V06: cancellation during resource setup is propagated before further files load")
func cancelResourceLoad() throws {
    var calls = 0
    #expect(throws: CancellationError.self) {
        try SolverResources.load(from:SolverResources.bundledDirectory()) {
            calls += 1
            if calls == 4 { throw CancellationError() }
        }
    }
    #expect(calls == 4)
}
