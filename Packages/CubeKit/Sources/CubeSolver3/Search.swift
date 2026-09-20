import CubeCore

package enum SearchError: Error { case exhaustedBounds, invalidBounds }
package enum SearchPhase: Sendable { case starting, phaseOne, phaseTwo, finished }
package struct SearchBounds: Sendable {
  package let phaseOne: Int, phaseTwo: Int
  package init(phaseOne: Int = 12, phaseTwo: Int = 18) {
    self.phaseOne = phaseOne
    self.phaseTwo = phaseTwo
  }
}

package enum SearchEngine {
  package static func phaseOne(_ state: Cubies, tables: SolverTables, maximumDepth: Int) throws
    -> [Move]
  {
    try SearchJob(tables: tables, check: { _, _ in }).firstPhase(state, maximumDepth: maximumDepth)
  }
  package static func phaseTwo(_ state: Cubies, tables: SolverTables, maximumDepth: Int) throws
    -> [Move]
  {
    try SearchJob(tables: tables, check: { _, _ in }).secondPhase(state, maximumDepth: maximumDepth)
  }
  package static func solve(
    _ cube: LegalCube, tables: SolverTables, bounds: SearchBounds = SearchBounds(),
    check: @escaping (SearchPhase, Int) throws -> Void = { _, _ in }
  ) throws -> [Move] {
    let job = SearchJob(tables: tables, check: check)
    try check(.starting, 0)
    let original = try Cubies(cube: cube)
    let first = try job.firstPhase(original, maximumDepth: bounds.phaseOne)
    let subgroup = first.reduce(original) { $0.applying($1) }
    // Phase two deliberately starts with no previous face from phase one.
    let second = try job.secondPhase(subgroup, maximumDepth: bounds.phaseTwo)
    try check(.finished, job.visited)
    return first + second
  }
}

/// One mutable job, created and consumed synchronously on the solver worker.
private final class SearchJob {
  private let twistMove: [UInt16], flipMove: [UInt16], sliceMove: [UInt16]
  private let cornerMove: [UInt16], edgeMove: [UInt16], slicePermMove: [UInt16]
  private let twistDistance: [UInt16], flipDistance: [UInt16], cornerDistance: [UInt16],
    edgeDistance: [UInt16]
  private let check: (SearchPhase, Int) throws -> Void
  private var pathOne: [Move] = [], pathTwo: [Move] = []
  private(set) var visited = 0

  init(tables: SolverTables, check: @escaping (SearchPhase, Int) throws -> Void) {
    twistMove = tables[.twistMove]
    flipMove = tables[.flipMove]
    sliceMove = tables[.sliceMove]
    cornerMove = tables[.cornerPermMove]
    edgeMove = tables[.edgePermMove]
    slicePermMove = tables[.slicePermMove]
    twistDistance = tables[.twistSliceDistance]
    flipDistance = tables[.flipSliceDistance]
    cornerDistance = tables[.cornerSlicePermDistance]
    edgeDistance = tables[.edgeSlicePermDistance]
    self.check = check
    pathOne.reserveCapacity(12)
    pathTwo.reserveCapacity(18)
  }

  func firstPhase(_ state: Cubies, maximumDepth: Int) throws -> [Move] {
    guard (0...12).contains(maximumDepth) else { throw SearchError.invalidBounds }
    try check(.phaseOne, visited)
    let twist = try Coordinates.twist(state.cornerOrientation)
    let flip = try Coordinates.flip(state.edgeOrientation)
    let slice = try Coordinates.slice(state.edgePermutation)
    let lower = heuristicOne(twist, flip, slice)
    guard lower <= maximumDepth else { throw SearchError.exhaustedBounds }
    for depth in lower...maximumDepth {
      try check(.phaseOne, visited)
      pathOne.removeAll(keepingCapacity: true)
      if try searchOne(twist, flip, slice, remaining: depth, previous: -1) { return pathOne }
    }
    throw SearchError.exhaustedBounds
  }

  func secondPhase(_ state: Cubies, maximumDepth: Int) throws -> [Move] {
    guard (0...18).contains(maximumDepth) else { throw SearchError.invalidBounds }
    try check(.phaseTwo, visited)
    let coordinate = try state.phaseTwoCoordinates()
    let lower = heuristicTwo(coordinate.corners, coordinate.edges, coordinate.slice)
    guard lower <= maximumDepth else { throw SearchError.exhaustedBounds }
    for depth in lower...maximumDepth {
      try check(.phaseTwo, visited)
      pathTwo.removeAll(keepingCapacity: true)
      if try searchTwo(
        coordinate.corners, coordinate.edges, coordinate.slice, remaining: depth, previous: -1)
      {
        return pathTwo
      }
    }
    throw SearchError.exhaustedBounds
  }

  private func heuristicOne(_ twist: Int, _ flip: Int, _ slice: Int) -> Int {
    Int(max(twistDistance[twist * 495 + slice], flipDistance[flip * 495 + slice]))
  }
  private func heuristicTwo(_ corners: Int, _ edges: Int, _ slice: Int) -> Int {
    Int(max(cornerDistance[corners * 24 + slice], edgeDistance[edges * 24 + slice]))
  }
  private func visit(_ phase: SearchPhase) throws {
    visited += 1
    if visited & 1023 == 0 { try check(phase, visited) }
  }

  private func searchOne(_ twist: Int, _ flip: Int, _ slice: Int, remaining: Int, previous: Int)
    throws -> Bool
  {
    try visit(.phaseOne)
    guard heuristicOne(twist, flip, slice) <= remaining else { return false }
    if twist == 0 && flip == 0 && slice == 494 { return true }
    guard remaining > 0 else { return false }
    for index in 0..<18 {
      let face = index / 3
      if face == previous { continue }
      let move = SolverMoves.phaseOne[index]
      pathOne.append(move)
      if try searchOne(
        Int(twistMove[twist * 18 + index]), Int(flipMove[flip * 18 + index]),
        Int(sliceMove[slice * 18 + index]), remaining: remaining - 1, previous: face)
      {
        return true
      }
      pathOne.removeLast()
    }
    return false
  }

  private func searchTwo(_ corners: Int, _ edges: Int, _ slice: Int, remaining: Int, previous: Int)
    throws -> Bool
  {
    try visit(.phaseTwo)
    guard heuristicTwo(corners, edges, slice) <= remaining else { return false }
    if corners == 0 && edges == 0 && slice == 0 { return true }
    guard remaining > 0 else { return false }
    for index in 0..<10 {
      let move = SolverMoves.phaseTwo[index]
      let face = Int(move.face.rawValue)
      if face == previous { continue }
      pathTwo.append(move)
      if try searchTwo(
        Int(cornerMove[corners * 10 + index]), Int(edgeMove[edges * 10 + index]),
        Int(slicePermMove[slice * 10 + index]), remaining: remaining - 1, previous: face)
      {
        return true
      }
      pathTwo.removeLast()
    }
    return false
  }
}
