import Foundation
import SwiftUI
import Testing

@testable import ModelSwitchboardApp

@Test func settingsChromeOptionalStringClearsToNil() {
    final class Box: @unchecked Sendable {
        var stored: String? = "kept"
    }
    let box = Box()
    let text = SettingsChrome.optionalString(
        Binding(get: { box.stored }, set: { box.stored = $0 })
    )
    #expect(text.wrappedValue == "kept")
    text.wrappedValue = "next"
    #expect(box.stored == "next")
    text.wrappedValue = ""
    #expect(box.stored == nil)
    #expect(text.wrappedValue == "")
}
