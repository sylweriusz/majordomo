import Foundation

public struct DoubleEscapeDetector: Sendable {
    public let maximumInterval: TimeInterval
    private var previousEscapeTimestamp: TimeInterval?

    public init(maximumInterval: TimeInterval = 0.45) {
        self.maximumInterval = maximumInterval
    }

    public mutating func recordKey(isEscape: Bool, at timestamp: TimeInterval) -> Bool {
        guard isEscape else {
            reset()
            return false
        }

        if let previousEscapeTimestamp,
           timestamp - previousEscapeTimestamp <= maximumInterval {
            reset()
            return true
        }

        previousEscapeTimestamp = timestamp
        return false
    }

    public mutating func reset() {
        previousEscapeTimestamp = nil
    }
}
