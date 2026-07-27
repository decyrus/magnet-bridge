import AppKit
import Foundation

extension NSWorkspace {
  /// Opens `url` with the application at `applicationURL`, bridging the
  /// completion-handler API onto Swift concurrency.
  public func open(_ url: URL, withApplicationAt applicationURL: URL) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      open(
        [url],
        withApplicationAt: applicationURL,
        configuration: NSWorkspace.OpenConfiguration()
      ) { _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }
}
