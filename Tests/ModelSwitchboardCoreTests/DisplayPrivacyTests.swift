import Foundation
import Testing
import ModelSwitchboardCore

/// Screen-share privacy masking: host-identifying strings hide; ports, paths,
/// names, and metrics survive. All call sites take `hidden:` explicitly so the
/// tests do not depend on (or mutate) global UserDefaults state.
@Test func displayPrivacyMasksHosts() {
    #expect(DisplayPrivacy.host("dgx-spark.tail01763b.ts.net", hidden: true) == "••••")
    #expect(DisplayPrivacy.host("100.122.96.76", hidden: true) == "••••")
    #expect(DisplayPrivacy.host("aditya@spark-1672.local", hidden: true) == "••••")
    #expect(DisplayPrivacy.host("spark", hidden: false) == "spark")
    #expect(DisplayPrivacy.host(nil, hidden: true) == "")
    #expect(DisplayPrivacy.host("", hidden: true) == "")
}

@Test func displayPrivacyKeepsPortsAndURLShapes() {
    #expect(DisplayPrivacy.hostPort("127.0.0.1", port: "8050", hidden: true) == "••••:8050")
    #expect(DisplayPrivacy.hostPort("127.0.0.1", port: "8050", hidden: false) == "127.0.0.1:8050")

    #expect(
        DisplayPrivacy.url("http://dgx-spark.tail01763b.ts.net:8050/v1", hidden: true)
            == "http://••••:8050/v1"
    )
    #expect(
        DisplayPrivacy.url("http://100.122.96.76:8877", hidden: false)
            == "http://100.122.96.76:8877"
    )
    // Unparseable junk masks whole rather than leaking.
    #expect(DisplayPrivacy.url("not a url at all", hidden: true) == "••••")
}

@Test func displayPrivacyConnectionSummary() {
    #expect(
        DisplayPrivacy.connectionSummary("ssh aditya@spark.local → 127.0.0.1:8877", hidden: true)
            == "•••• → 127.0.0.1:8877"
    )
    #expect(
        DisplayPrivacy.connectionSummary("ssh aditya@spark.local → 127.0.0.1:8877", hidden: false)
            == "ssh aditya@spark.local → 127.0.0.1:8877"
    )
    #expect(
        DisplayPrivacy.connectionSummary("http://spark.tail1234.ts.net:8877", hidden: true)
            == "http://••••:8877"
    )
    #expect(DisplayPrivacy.connectionSummary("weird plain host", hidden: true) == "••••")
}
