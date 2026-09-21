import Foundation

@MainActor
final class PreviewDeadline: PreviewDeadlineScheduler {
  private var task: Task<Void, Never>?
  private var generation: UUID?

  func schedule(after delay: Duration, _ completion: @escaping @MainActor () -> Void) {
    cancel()
    let token = UUID()
    generation = token
    task = Task { [weak self] in
      do { try await Task.sleep(for: max(.zero, delay), clock: .continuous) }
      catch { return }
      guard !Task.isCancelled, let self, self.generation == token else { return }
      self.generation = nil
      self.task = nil
      completion()
    }
  }

  func cancel() {
    generation = nil
    task?.cancel()
    task = nil
  }

  deinit { task?.cancel() }
}
