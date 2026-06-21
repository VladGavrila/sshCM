import Testing
@testable import sshCMUtilities

@Suite("SemanticVersion – parsing")
struct SemanticVersionParsingTests {

    @Test func basicParsing() {
        let v = SemanticVersion("1.2.3")
        #expect(v?.major == 1)
        #expect(v?.minor == 2)
        #expect(v?.patch == 3)
    }

    @Test func lowercaseVPrefix() {
        let v = SemanticVersion("v1.2.3")
        #expect(v?.major == 1 && v?.minor == 2 && v?.patch == 3)
    }

    @Test func uppercaseVPrefix() {
        let v = SemanticVersion("V1.2.3")
        #expect(v?.major == 1 && v?.minor == 2 && v?.patch == 3)
    }

    @Test func preReleaseSuffixIgnored() {
        let v = SemanticVersion("1.2.3-beta.1")
        #expect(v?.major == 1 && v?.minor == 2 && v?.patch == 3)
    }

    @Test func buildMetadataSuffixIgnored() {
        let v = SemanticVersion("1.2.3+20231201")
        #expect(v?.major == 1 && v?.minor == 2 && v?.patch == 3)
    }

    @Test func majorOnlyDefaultsMinorPatchToZero() {
        let v = SemanticVersion("2")
        #expect(v?.major == 2 && v?.minor == 0 && v?.patch == 0)
    }

    @Test func majorMinorDefaultsPatchToZero() {
        let v = SemanticVersion("2.1")
        #expect(v?.major == 2 && v?.minor == 1 && v?.patch == 0)
    }

    @Test func nonNumericMajorReturnsNil() {
        #expect(SemanticVersion("x.1.0") == nil)
    }

    @Test func emptyStringReturnsNil() {
        #expect(SemanticVersion("") == nil)
    }

    @Test func leadingTrailingWhitespaceStripped() {
        #expect(SemanticVersion("  1.2.3  ")?.description == "1.2.3")
    }

    @Test func descriptionIsCompact() {
        #expect(SemanticVersion("1.2.3")?.description  == "1.2.3")
        #expect(SemanticVersion("2.0.0")?.description  == "2.0.0")
        #expect(SemanticVersion("1")?.description      == "1.0.0")
        #expect(SemanticVersion("v0.9.1")?.description == "0.9.1")
    }
}

@Suite("SemanticVersion – comparison")
struct SemanticVersionComparisonTests {

    @Test func majorVersionDominates() {
        #expect(SemanticVersion("2.0.0")! > SemanticVersion("1.9.9")!)
        #expect(SemanticVersion("1.0.0")! < SemanticVersion("2.0.0")!)
    }

    @Test func minorVersionDominatesWhenMajorEqual() {
        #expect(SemanticVersion("1.2.0")! > SemanticVersion("1.1.9")!)
        #expect(SemanticVersion("1.1.0")! < SemanticVersion("1.2.0")!)
    }

    @Test func patchVersionDominatesWhenMajorMinorEqual() {
        #expect(SemanticVersion("1.0.2")! > SemanticVersion("1.0.1")!)
        #expect(SemanticVersion("1.0.1")! < SemanticVersion("1.0.2")!)
    }

    @Test func equalVersionsCompareEqual() {
        let a = SemanticVersion("1.2.3")!
        let b = SemanticVersion("1.2.3")!
        #expect(a == b)
        #expect(!(a < b))
        #expect(!(a > b))
    }

    @Test func sortableCollection() {
        let input   = ["1.10.0", "1.9.0", "2.0.0", "1.0.1"].compactMap { SemanticVersion($0) }
        let sorted  = input.sorted().map(\.description)
        #expect(sorted == ["1.0.1", "1.9.0", "1.10.0", "2.0.0"])
    }

    @Test func maxOfCollection() {
        let versions = ["1.0.0", "2.0.0", "1.5.0"].compactMap { SemanticVersion($0) }
        #expect(versions.max()?.description == "2.0.0")
    }

    @Test func zeroVersionIsLowest() {
        #expect(SemanticVersion("0.0.0")! < SemanticVersion("0.0.1")!)
    }
}
