/// Back/forward history of a browser window, like a web browser's.
public struct NavigationHistory<Location: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var backStack: [Location] = []
    public private(set) var current: Location
    public private(set) var forwardStack: [Location] = []

    public init(start: Location) {
        current = start
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    /// Visits a new location. Going somewhere new drops the forward history.
    /// Visiting the current location again changes nothing.
    public mutating func go(to location: Location) {
        guard location != current else { return }
        backStack.append(current)
        current = location
        forwardStack.removeAll()
    }

    @discardableResult
    public mutating func goBack() -> Location? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return current
    }

    @discardableResult
    public mutating func goForward() -> Location? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return current
    }
}
