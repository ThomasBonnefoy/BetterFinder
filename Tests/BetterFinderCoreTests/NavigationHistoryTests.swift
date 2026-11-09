import Testing
@testable import BetterFinderCore

@Suite struct NavigationHistoryTests {
    @Test func startsWithNothingToGoBackTo() {
        let history = NavigationHistory(start: "home")
        #expect(history.current == "home")
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test func goesBackAndForward() {
        var history = NavigationHistory(start: "a")
        history.go(to: "b")
        history.go(to: "c")

        #expect(history.goBack() == "b")
        #expect(history.goBack() == "a")
        #expect(history.goBack() == nil)
        #expect(history.current == "a")

        #expect(history.goForward() == "b")
        #expect(history.goForward() == "c")
        #expect(history.goForward() == nil)
        #expect(history.current == "c")
    }

    @Test func goingSomewhereNewDropsForwardHistory() {
        var history = NavigationHistory(start: "a")
        history.go(to: "b")
        history.goBack()
        history.go(to: "c")

        #expect(!history.canGoForward)
        #expect(history.backStack == ["a"])
        #expect(history.current == "c")
    }

    @Test func revisitingTheCurrentLocationChangesNothing() {
        var history = NavigationHistory(start: "a")
        history.go(to: "b")
        history.goBack()
        history.go(to: "a")

        #expect(!history.canGoBack)
        #expect(history.canGoForward)
    }

    @Test func replacingTheCurrentLocationKeepsBothStacks() {
        var history = NavigationHistory(start: "a")
        history.go(to: "placeholder")
        history.go(to: "c")
        history.goBack()
        history.replaceCurrent(with: "b")

        #expect(history.current == "b")
        #expect(history.backStack == ["a"])
        #expect(history.forwardStack == ["c"])
    }
}
