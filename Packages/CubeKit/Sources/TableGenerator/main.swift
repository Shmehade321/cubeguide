import CubeTableTools
import CubeSolver3
import Foundation

// No generation code ships in the iPhone target. Manifest is written last.
do {
    guard CommandLine.arguments.count == 3 else {
        throw NSError(domain:"TableGenerator",code:64,userInfo:[NSLocalizedDescriptionKey:"Usage: TableGenerator EMPTY_OUTPUT_DIRECTORY GENERATOR_SOURCE_COMMIT"])
    }
    let directory = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
    let source = CommandLine.arguments[2]
    guard source.range(of:"^[0-9a-f]{40}$",options:.regularExpression) != nil else {
        throw NSError(domain:"TableGenerator",code:64,userInfo:[NSLocalizedDescriptionKey:"Expected full source commit SHA"])
    }
    let manager = FileManager.default
    if manager.fileExists(atPath:directory.path) {
        guard try manager.contentsOfDirectory(atPath:directory.path).isEmpty else {
            throw NSError(domain:"TableGenerator",code:64,userInfo:[NSLocalizedDescriptionKey:"Output directory must be empty"])
        }
    } else { try manager.createDirectory(at:directory,withIntermediateDirectories:true) }
    let started = ContinuousClock.now
    let tables = try TableBuilder.allTables { print("Generated \($0.filename)") }
    var records: [[String:Any]] = []
    for table in tables {
        let bytes = TableCodec.encode(table)
        try bytes.write(to:directory.appendingPathComponent(table.id.filename),options:.atomic)
        records.append(["identifier":table.id.rawValue,"filename":table.id.filename,"rows":table.id.rows,
                        "columns":table.id.columns,"elementWidth":table.id.width,"byteCount":bytes.count,"sha256":TableCodec.digest(bytes)])
    }
    let manifest: [String:Any] = ["formatVersion":1,"generatorVersion":"cubeguide-tables-v1","sourceCommit":source,"tables":records]
    let bytes = try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys])
    try bytes.write(to:directory.appendingPathComponent("manifest.json"),options:.atomic)
    print("Completed \(tables.count) tables in \(started.duration(to:.now)); payload \(tables.reduce(0){$0+$1.id.count*$1.id.width}) bytes")
} catch {
    FileHandle.standardError.write(Data("Table generation failed: \(error)\n".utf8))
    exit(1)
}
