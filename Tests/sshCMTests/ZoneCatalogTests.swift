import Testing
@testable import sshCMModels

@Suite("ZoneCatalog")
struct ZoneCatalogTests {

    @Test func normalizedTrimsWhitespace() {
        #expect(ZoneCatalog.normalized("  home  ") == "home")
    }

    @Test func normalizedPreservesCase() {
        #expect(ZoneCatalog.normalized("HomeOffice") == "HomeOffice")
    }

    @Test func normalizedAllowsHostnameSafeCharacters() {
        #expect(ZoneCatalog.normalized("home-office_1.lan") == "home-office_1.lan")
    }

    @Test func normalizedRejectsEmptyOrWhitespaceOnly() {
        #expect(ZoneCatalog.normalized("") == nil)
        #expect(ZoneCatalog.normalized("   ") == nil)
    }

    @Test func normalizedRejectsInteriorSpaces() {
        #expect(ZoneCatalog.normalized("Home Office") == nil)
    }

    @Test func normalizedRejectsSpecialCharacters() {
        #expect(ZoneCatalog.normalized("home/office") == nil)
        #expect(ZoneCatalog.normalized("home,office") == nil)
    }

    @Test func normalizedRejectsMultiline() {
        #expect(ZoneCatalog.normalized("home\nwork") == nil)
    }

    @Test func sanitizeInputStripsDisallowedCharacters() {
        #expect(ZoneCatalog.sanitizeInput("home office!") == "homeoffice")
        #expect(ZoneCatalog.sanitizeInput("home-office_1.lan") == "home-office_1.lan")
    }

    @Test func isDuplicateIsCaseInsensitive() {
        #expect(ZoneCatalog.isDuplicate("HOME", in: ["home", "work"]))
        #expect(ZoneCatalog.isDuplicate("home", in: ["Home"]))
        #expect(!ZoneCatalog.isDuplicate("aws", in: ["home", "work"]))
    }

    @Test func reconciledPreservesDeclaredOrder() {
        let result = ZoneCatalog.reconciled(declared: ["home", "work", "aws"], hostZones: ["work", "home"])
        #expect(result == ["home", "work", "aws"])
    }

    @Test func reconciledAppendsUnknownZonesInFirstSeenOrder() {
        let result = ZoneCatalog.reconciled(declared: ["home"], hostZones: ["garage", "office", "garage"])
        #expect(result == ["home", "garage", "office"])
    }

    @Test func reconciledCollapsesDuplicatesInHostZones() {
        let result = ZoneCatalog.reconciled(declared: [], hostZones: ["aws", "AWS", "aws"])
        #expect(result == ["aws"])
    }

    @Test func reconciledEmptyDeclaredAndEmptyHostsIsEmpty() {
        #expect(ZoneCatalog.reconciled(declared: [], hostZones: []).isEmpty)
    }

    @Test func reconciledIsNoOpWhenNothingNew() {
        let declared = ["home", "work"]
        let result = ZoneCatalog.reconciled(declared: declared, hostZones: ["home"])
        #expect(result == declared)
    }
}
