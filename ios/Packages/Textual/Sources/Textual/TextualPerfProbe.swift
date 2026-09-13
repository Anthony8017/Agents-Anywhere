import Foundation
import SwiftUI

/// Opt-in diagnostics. Counters and experiments stay disabled without launch environment flags.
public enum TextualPerfProbe {
  public static let enabled = ProcessInfo.processInfo.environment["AA_PERF_COUNTERS"] == "1"
  public static let noSelection = ProcessInfo.processInfo.environment["AA_PERF_SELECTION"] == "off"
  public static let resolvedEquality = ProcessInfo.processInfo.environment["AA_PERF_LAYOUT_EQUALITY"] == "resolved"
  public static let viewportSelection = ProcessInfo.processInfo.environment["AA_PERF_VIEWPORT_SELECTION"] == "1"
  public static let noNativeOverlay = ProcessInfo.processInfo.environment["AA_PERF_NATIVE_OVERLAY"] == "off"
  public static let viewportNative = ProcessInfo.processInfo.environment["AA_PERF_NATIVE_VIEWPORT"] == "1"
  public static let noLayoutReader = ProcessInfo.processInfo.environment["AA_PERF_LAYOUT_READER"] == "off"
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

@MainActor extension EnvironmentValues {
  @Entry var probeNativeSelectionActive = true
}
