import Foundation

/// Diagnostic worktree only. Disabled unless the probe launch enables counters.
public enum TextualPerfProbe {
  public static let enabled = ProcessInfo.processInfo.environment["AA_PERF_COUNTERS"] == "1"
  public static let noSelection = ProcessInfo.processInfo.environment["AA_PERF_SELECTION"] == "off"
  public static let resolvedEquality = ProcessInfo.processInfo.environment["AA_PERF_LAYOUT_EQUALITY"] == "resolved"
  private static let lock = NSLock()
  nonisolated(unsafe) private static var counts: [String: Int] = [:]

  public static func hit(_ name: String) {
    guard enabled else { return }
    lock.lock(); counts[name, default: 0] += 1; lock.unlock()
  }

  public static func take() -> [String: Int] {
    lock.lock(); defer { lock.unlock() }
    let value = counts; counts.removeAll(keepingCapacity: true); return value
  }
}
