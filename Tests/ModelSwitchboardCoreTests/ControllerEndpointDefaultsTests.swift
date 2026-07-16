import Foundation
import Testing
import ModelSwitchboardCore

struct ControllerEndpointDefaultsTests {
    @Test func sharedLoopbackEndpointMatchesHistoricalDefaults() {
        #expect(ControllerEndpointDefaults.host == "127.0.0.1")
        #expect(ControllerEndpointDefaults.port == 8877)
        #expect(ControllerEndpointDefaults.baseURLString == "http://127.0.0.1:8877")
        #expect(ControllerEndpointDefaults.baseURLUserDefaultsKey == "controllerBaseURL")
    }
}
