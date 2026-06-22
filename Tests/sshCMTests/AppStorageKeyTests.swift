import Testing
@testable import sshCMModels

@Suite("AppStorageKey")
struct AppStorageKeyTests {

    @Test func allKeysAreUnique() {
        let keys = AppStorageKey.allCases.map(\.rawValue)
        #expect(keys.count == Set(keys).count,
                "Duplicate UserDefaults key found — silent data loss risk")
    }

    @Test func keyCountMatchesExpected() {
        // Guard against accidentally adding a duplicate or removing a key.
        // Update this number whenever a key is intentionally added or removed.
        #expect(AppStorageKey.allCases.count == 18)
    }

    @Test func knownKeysHaveCorrectRawValues() {
        #expect(AppStorageKey.favoriteAliases.rawValue      == "favoriteAliases")
        #expect(AppStorageKey.hostTags.rawValue             == "hostTags")
        #expect(AppStorageKey.hostTagOrder.rawValue         == "hostTagOrder")
        #expect(AppStorageKey.hostTagNames.rawValue         == "hostTagNames")
        #expect(AppStorageKey.hostKeyBypassAliases.rawValue == "hostKeyBypassAliases")
        #expect(AppStorageKey.publishAliasesToHostsFile.rawValue == "publishAliasesToHostsFile")
        #expect(AppStorageKey.autoCheckForUpdates.rawValue  == "autoCheckForUpdates")
        #expect(AppStorageKey.updateLastCheck.rawValue      == "updateLastCheck")
        #expect(AppStorageKey.skippedUpdateVersion.rawValue == "skippedUpdateVersion")
        #expect(AppStorageKey.keepTerminalOpenAfterSession.rawValue == "keepTerminalOpenAfterSession")
        #expect(AppStorageKey.appPresentation.rawValue      == "appPresentation")
        #expect(AppStorageKey.defaultTerminalAppPath.rawValue == "defaultTerminalAppPath")
        #expect(AppStorageKey.hostsViewMode.rawValue        == "hostsViewMode")
        #expect(AppStorageKey.showOnlyReachable.rawValue    == "showOnlyReachable")
        #expect(AppStorageKey.defaultPublicKeyPath.rawValue == "defaultPublicKeyPath")
        #expect(AppStorageKey.defaultMacOSVNCAppPath.rawValue == "defaultMacOSVNCAppPath")
        #expect(AppStorageKey.defaultLinuxVNCAppPath.rawValue == "defaultLinuxVNCAppPath")
        #expect(AppStorageKey.remoteAccessApps.rawValue == "remoteAccessApps")
    }
}
