import Foundation

/// Injectable time source so tests can control "now" for recency / age thresholds
/// without racing the real clock.
public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

public struct FixedClock: Clock {
    public let fixedDate: Date
    public init(_ date: Date) { self.fixedDate = date }
    public func now() -> Date { fixedDate }
}
