import Testing
@testable import MacOrganizer

@Suite("App target smoke tests")
struct MacOrganizerSmokeTests {
    @Test func navigationDestinationsCoverAllCases() {
        let all = Set(NavigationDestination.primary + NavigationDestination.secondary)
        #expect(all == Set(NavigationDestination.allCases))
    }

    @Test func everyDestinationHasASymbol() {
        for destination in NavigationDestination.allCases {
            #expect(!destination.symbolName.isEmpty)
        }
    }
}
