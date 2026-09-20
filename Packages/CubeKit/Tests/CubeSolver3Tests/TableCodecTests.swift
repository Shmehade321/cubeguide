import CryptoKit
import Foundation
import Testing
@testable import CubeSolver3

private func digest(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }

@Test("V04: table header is explicit little-endian and round-trips without native layouts")
func tableBinaryRoundTrip() throws {
    let values = (0..<240).map { UInt16($0%24) }
    let table = try SolverTable(id:.slicePermMove,values:values)
    let bytes = TableCodec.encode(table)
    try #require(bytes.count == 276)
    #expect(Array(bytes.prefix(36)) == [67,85,66,69,84,66,76,49, 1,0,0,0, 6,0,0,0, 24,0,0,0, 10,0,0,0, 1,0,0,0, 240,0,0,0,0,0,0,0])
    #expect(try TableCodec.decode(bytes,id:.slicePermMove,sha256:digest(bytes)) == table)
    let wide = try SolverTable(id:.twistMove, values:Array(repeating:UInt16(258),count:2187*18))
    let wideBytes = TableCodec.encode(wide)
    #expect(Array(wideBytes[36..<40]) == [2,1,2,1])
    #expect(try TableCodec.decode(wideBytes,id:.twistMove,sha256:digest(wideBytes)) == wide)
}

@Test("V04: malformed table headers, payloads and integrity failures are rejected")
func malformedTables() throws {
    let table = try SolverTable(id:.slicePermMove,values:Array(repeating:0,count:240))
    let bytes = TableCodec.encode(table)
    #expect(throws: TableError.self) { try TableCodec.decode(bytes,id:.slicePermMove,sha256:String(repeating:"0",count:64)) }
    for offset in [0,8,12,16,20,24,28,35] {
        var corrupt = bytes
        if offset < corrupt.count { corrupt[offset] = 255 }
        #expect(throws: TableError.self) { try TableCodec.decode(corrupt,id:.slicePermMove,sha256:digest(corrupt)) }
    }
    for malformed in [Data(),Data(bytes.dropLast()),bytes+Data([0])] {
        #expect(throws: TableError.self) { try TableCodec.decode(malformed,id:.slicePermMove,sha256:digest(malformed)) }
    }
    var badValue = bytes
    if badValue.count > 36 { badValue[36] = 24 }
    #expect(throws: TableError.self) { try TableCodec.decode(badValue,id:.slicePermMove,sha256:digest(badValue)) }
}

@Test("V04: table constructors reject wrong shape, transition ranges and unresolved distances")
func malformedTableValues() {
    #expect(throws: TableError.self) { try SolverTable(id:.slicePermMove,values:[]) }
    #expect(throws: TableError.self) { try SolverTable(id:.slicePermMove,values:Array(repeating:24,count:240)) }
    #expect(throws: TableError.self) { try SolverTable(id:.twistMove,values:Array(repeating:2187,count:2187*18)) }
    #expect(throws: TableError.self) { try SolverTable(id:.twistSliceDistance,values:Array(repeating:255,count:2187*495)) }
}
