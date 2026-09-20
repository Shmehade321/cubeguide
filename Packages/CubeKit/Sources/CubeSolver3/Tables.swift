import CryptoKit
import Foundation

public enum TableError: Error { case invalidShape, invalidValue, invalidHeader, invalidSize, hashMismatch }

package enum TableID: UInt32, CaseIterable, Sendable, Codable {
    case twistMove = 1, flipMove, sliceMove, cornerPermMove, edgePermMove, slicePermMove
    case twistSliceDistance, flipSliceDistance, cornerSlicePermDistance, edgeSlicePermDistance

    package var rows: Int {
        switch self {
        case .twistMove,.twistSliceDistance: 2187
        case .flipMove,.flipSliceDistance: 2048
        case .sliceMove: 495
        case .slicePermMove: 24
        case .cornerPermMove,.edgePermMove,.cornerSlicePermDistance,.edgeSlicePermDistance: 40320
        }
    }
    package var columns: Int {
        switch self {
        case .twistMove,.flipMove,.sliceMove: 18
        case .cornerPermMove,.edgePermMove,.slicePermMove: 10
        case .twistSliceDistance,.flipSliceDistance: 495
        case .cornerSlicePermDistance,.edgeSlicePermDistance: 24
        }
    }
    package var width: Int { rawValue <= 5 ? 2 : 1 }
    package var count: Int { rows*columns }
    package var byteCount: Int { 36+count*width }
    package var filename: String { String(describing:self)+".bin" }
    package var valueLimit: Int { rawValue <= 6 ? rows : 255 }
}

package struct SolverTable: Equatable, Sendable {
    package let id: TableID
    package let values: [UInt16]
    package init(id: TableID, values: [UInt16]) throws {
        guard values.count == id.count else { throw TableError.invalidShape }
        guard values.allSatisfy({ Int($0) < id.valueLimit }) else { throw TableError.invalidValue }
        self.id=id;self.values=values
    }
}

package enum TableCodec {
    package static func digest(_ data: Data) -> String {
        SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
    }

    package static func encode(_ table: SolverTable) -> Data {
        var bytes = Array("CUBETBL1".utf8)
        bytes.reserveCapacity(table.id.byteCount)
        func append(_ value: UInt64, width: Int) {
            for byte in 0..<width { bytes.append(UInt8(truncatingIfNeeded:value >> (byte*8))) }
        }
        append(1,width:4)
        append(UInt64(table.id.rawValue),width:4)
        append(UInt64(table.id.rows),width:4)
        append(UInt64(table.id.columns),width:4)
        append(UInt64(table.id.width),width:4)
        append(UInt64(table.id.count*table.id.width),width:8)
        for value in table.values { append(UInt64(value),width:table.id.width) }
        return Data(bytes)
    }

    package static func decode(_ data: Data, id: TableID, sha256: String) throws -> SolverTable {
        // All allocation bounds come from fixed versioned dimensions, never an untrusted header.
        guard data.count == id.byteCount else { throw TableError.invalidSize }
        guard digest(data) == sha256 else { throw TableError.hashMismatch }
        let bytes = Array(data)
        func integer(_ offset: Int, width: Int) -> UInt64 {
            (0..<width).reduce(UInt64(0)) { $0 | UInt64(bytes[offset+$1]) << ($1*8) }
        }
        guard bytes.prefix(8).elementsEqual("CUBETBL1".utf8),
              integer(8,width:4) == 1,
              integer(12,width:4) == id.rawValue,
              integer(16,width:4) == id.rows,
              integer(20,width:4) == id.columns,
              integer(24,width:4) == id.width,
              integer(28,width:8) == UInt64(id.count*id.width) else { throw TableError.invalidHeader }
        let values = (0..<id.count).map { UInt16(integer(36+$0*id.width,width:id.width)) }
        return try SolverTable(id:id,values:values)
    }
}
