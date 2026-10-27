import Foundation
import Testing

@testable import ClipBar

@Test func releaseBuildAcceptsGitHubFeedWithEd25519Key() {
    let info: [String: Any] = [
        "SUFeedURL": "https://github.com/lljxww/ClipBar/releases/latest/download/appcast.xml",
        "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
    ]
    #expect(UpdateConfiguration(info: info)?.feedURL.host == "github.com")
}

@Test func unconfiguredOrUnsafeUpdateSourcesAreDisabled() {
    #expect(UpdateConfiguration(info: [:]) == nil)
    let key = Data(repeating: 1, count: 32).base64EncodedString()
    for feed in [
        "http://github.com/owner/repo/releases/latest/download/appcast.xml",
        "https://github.com.example.org/owner/repo/releases/latest/download/appcast.xml",
        "https://github.com/owner/repo/releases/latest/download/other.xml",
        "https://user@github.com/owner/repo/releases/latest/download/appcast.xml",
        "https://github.com:443/owner/repo/releases/latest/download/appcast.xml",
        "https://github.com/owner/repo/releases/latest/download/appcast.xml?token=secret",
    ] {
        #expect(UpdateConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": key]) == nil)
    }
    #expect(
        UpdateConfiguration(info: [
            "SUFeedURL": "https://github.com/owner/repo/releases/latest/download/appcast.xml",
            "SUPublicEDKey": Data(repeating: 1, count: 31).base64EncodedString(),
        ]) == nil)
}
