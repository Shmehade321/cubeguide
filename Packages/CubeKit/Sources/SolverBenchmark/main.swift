import CubeCore
import CubeSolver3
import Foundation

private struct CorpusCase: Decodable { let id: String, state: String, expectedValid: Bool }
private struct Measurement: Encodable {
  let id: String, state: String, outcome: String, elapsedSeconds: Double, visitedNodes: Int,
    resourceVersion: String?, solution: [String]?
}
private func seconds(_ duration: Duration) -> Double {
  let parts = duration.components
  return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
}

// Development harness only. Each cold invocation accepts exactly one case in a fresh process.
do {
  guard (2...3).contains(CommandLine.arguments.count) else {
    throw NSError(
      domain: "SolverBenchmark", code: 64,
      userInfo: [
        NSLocalizedDescriptionKey: "Usage: SolverBenchmark NEW_OUTPUT_JSONL [cold] < CORPUS_JSONL"
      ])
  }
  let cold = CommandLine.arguments.count == 3
  guard !cold || CommandLine.arguments[2] == "cold" else { throw CoordinateError.invalidValues }
  let path = CommandLine.arguments[1]
  guard !FileManager.default.fileExists(atPath: path),
    FileManager.default.createFile(atPath: path, contents: nil)
  else {
    throw NSError(
      domain: "SolverBenchmark", code: 64,
      userInfo: [NSLocalizedDescriptionKey: "Output must not already exist"])
  }
  let output = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
  defer { try? output.close() }
  let tableStart = ContinuousClock.now
  let tables: SolverTables? = cold ? nil : try SolverResources.loadBundled()
  FileHandle.standardError.write(
    Data("Table setup: \(tableStart.duration(to:.now)); mode \(cold ? "cold" : "warm")\n".utf8))
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  var count = 0
  var failures = 0
  while let line = readLine() {
    guard line.utf8.prefix(8193).count <= 8192, !cold || count == 0 else {
      throw CoordinateError.invalidValues
    }
    let input = try JSONDecoder().decode(CorpusCase.self, from: Data(line.utf8))
    let measurement: Measurement
    if let faces = try? Facelets(notation: input.state),
      case .success(let cube) = CubeValidation.validate(faces)
    {
      let result = SolverRuntime.run(cube: cube, tables: tables, budget: .extended)
      let status: String
      let solution: [String]?
      switch result.outcome {
      case .verified(let plan):
        status = "verified"
        solution = plan.moves.map(\.notation)
      case .cancelled:
        status = "cancelled"
        solution = nil
      case .timedOut:
        status = "timedOut"
        solution = nil
      case .invalidInput:
        status = "invalidInput"
        solution = nil
      case .resourceFailure:
        status = "resourceFailure"
        solution = nil
      case .verificationFailure:
        status = "verificationFailure"
        solution = nil
      case .invariantFailure:
        status = "invariantFailure"
        solution = nil
      }
      measurement = Measurement(
        id: input.id, state: input.state, outcome: status, elapsedSeconds: seconds(result.elapsed),
        visitedNodes: result.visitedNodes, resourceVersion: result.tables?.version,
        solution: solution)
      if !input.expectedValid || status != "verified" { failures += 1 }
    } else {
      measurement = Measurement(
        id: input.id, state: input.state, outcome: "invalidInput", elapsedSeconds: 0,
        visitedNodes: 0, resourceVersion: tables?.version, solution: nil)
      if input.expectedValid { failures += 1 }
    }
    var bytes = try encoder.encode(measurement)
    bytes.append(10)
    try output.write(contentsOf: bytes)
    count += 1
    if count % 1000 == 0 {
      FileHandle.standardError.write(Data("Completed \(count) cases; failures \(failures)\n".utf8))
    }
  }
  guard count > 0, failures == 0 else {
    throw NSError(
      domain: "SolverBenchmark", code: 1,
      userInfo: [
        NSLocalizedDescriptionKey:
          "\(failures) failed cases among \(count); retain output and investigate"
      ])
  }
  print("Completed \(count) cases; all expected outcomes matched.")
} catch {
  FileHandle.standardError.write(Data("Benchmark failed: \(error)\n".utf8))
  exit(1)
}
