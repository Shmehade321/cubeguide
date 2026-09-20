// Test-only geometry, independent of production's grid-rotation presentation and explicit move cycles.
import Testing
@testable import CubeCore

private struct Vector: Hashable {
    let x: Int, y: Int, z: Int
    init(_ x: Int, _ y: Int, _ z: Int) { self.x=x; self.y=y; self.z=z }
    static func + (a: Self, b: Self) -> Self { Self(a.x+b.x,a.y+b.y,a.z+b.z) }
    static func * (a: Self, k: Int) -> Self { Self(a.x*k,a.y*k,a.z*k) }
    func cross(_ b: Self) -> Self { Self(y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x) }
    func dot(_ b: Self) -> Int { x*b.x+y*b.y+z*b.z }
}
private struct Sticker: Hashable { let position: Vector; let normal: Vector }

@Test("V02: all view grids equal independent integer geometry and determinant +1")
func geometricPoses() throws {
    let normals = [Vector(0,1,0),Vector(1,0,0),Vector(0,0,1),Vector(0,-1,0),Vector(-1,0,0),Vector(0,0,-1)]
    let rights = [Vector(1,0,0),Vector(0,0,-1),Vector(1,0,0),Vector(1,0,0),Vector(0,0,1),Vector(-1,0,0)]
    let ups = [Vector(0,0,-1),Vector(0,1,0),Vector(0,1,0),Vector(0,0,1),Vector(0,1,0),Vector(0,1,0)]
    let stickers = (0..<54).map { i in
        Sticker(position: normals[i/9] + rights[i/9] * (i%3-1) + ups[i/9] * (1-i%9/3), normal: normals[i/9])
    }
    let indices = Dictionary(uniqueKeysWithValues: stickers.enumerated().map { ($0.element,$0.offset) })
    #expect(indices.count == 54)
    for pose in CubeOrientation.all {
        let x = normals[Int(pose.viewFace(for:.right).rawValue)]
        let y = normals[Int(pose.viewFace(for:.up).rawValue)]
        let z = normals[Int(pose.viewFace(for:.front).rawValue)]
        #expect(x.dot(y.cross(z)) == 1)
        func transformed(_ vector: Vector) -> Vector { x * vector.x + y * vector.y + z * vector.z }
        let viewed = pose.viewing(Array(0..<54))
        for (source,sticker) in stickers.enumerated() {
            let target = Sticker(position: transformed(sticker.position), normal: transformed(sticker.normal))
            let destination = try #require(indices[target])
            #expect(viewed[destination] == source)
        }
        #expect(pose.viewing(Facelets.solved).count == 54)
    }
}

@Test("V01: independent shallow oracle visits exactly 46,741 unique legal states through depth four")
func shallowStateOracle() throws {
    let solved = (0..<54).map { UInt8($0/9) }
    var visited: Set<[UInt8]> = [solved]
    var frontier: [[UInt8]] = [solved]
    var counts = [1]
    for _ in 1...4 {
        var next: [[UInt8]] = []
        for state in frontier {
            for permutation in goldenQuarterTurns {
                var moved = state
                for _ in 1...3 {
                    let old = moved
                    for source in 0..<54 { moved[permutation[source]] = old[source] }
                    if visited.insert(moved).inserted { next.append(moved) }
                }
            }
        }
        counts.append(next.count)
        frontier = next
    }
    #expect(counts == [1,18,243,3240,43239])
    #expect(visited.count == 46741)
    for state in visited {
        let facelets = try Facelets(state.map { Face.allCases[Int($0)] })
        #expect(try CubeValidation.validate(facelets).get().facelets == facelets)
    }
}
