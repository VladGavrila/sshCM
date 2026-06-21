import Testing
@testable import sshCMModels

@Suite("HostSearchScorer – score hierarchy")
struct HostSearchScorerTests {

    @Test func noMatchReturnsZero() {
        let host = SSHHost(aliases: ["prod"])
        #expect(HostSearchScorer.score(host: host, query: "zzz") == 0)
    }

    @Test func exactPrimaryAliasBeatsPrefixAlias() {
        let exact  = SSHHost(aliases: ["prod"])
        let prefix = SSHHost(aliases: ["production"])
        #expect(HostSearchScorer.score(host: exact,  query: "prod") >
                HostSearchScorer.score(host: prefix, query: "prod"))
    }

    @Test func prefixPrimaryAliasBeatContainsAlias() {
        let prefix   = SSHHost(aliases: ["prod-api"])
        let contains = SSHHost(aliases: ["api-prod-web"])
        #expect(HostSearchScorer.score(host: prefix,   query: "prod") >
                HostSearchScorer.score(host: contains, query: "prod"))
    }

    @Test func exactSearchAliasBeatsExactPrimaryAlias() {
        // Search alias exact (900) < primary alias exact (1000).
        let primary = SSHHost(aliases: ["prod"])
        let search  = SSHHost(aliases: ["server"], searchAliases: ["prod"])
        #expect(HostSearchScorer.score(host: primary, query: "prod") >
                HostSearchScorer.score(host: search,  query: "prod"))
    }

    @Test func searchAliasPrefixBeatsPrimaryContains() {
        // Search alias prefix (400+) > primary alias contains (100).
        let primaryContains  = SSHHost(aliases: ["api-production-web"])
        let searchAliasPrefix = SSHHost(aliases: ["server"], searchAliases: ["production"])
        #expect(HostSearchScorer.score(host: searchAliasPrefix, query: "prod") >
                HostSearchScorer.score(host: primaryContains,   query: "prod"))
    }

    @Test func otherFieldMatchHasLowestPositiveScore() {
        let byAlias = SSHHost(aliases: ["prod"])
        let byHost  = SSHHost(aliases: ["server"], hostName: "prod.example.com")
        #expect(HostSearchScorer.score(host: byAlias, query: "prod") >
                HostSearchScorer.score(host: byHost,  query: "prod"))
        #expect(HostSearchScorer.score(host: byHost, query: "prod") > 0)
    }

    @Test func tagNameMatchesAsOtherField() {
        let host = SSHHost(aliases: ["server"])
        #expect(HostSearchScorer.score(host: host, query: "prod", tagName: "Production") > 0)
        #expect(HostSearchScorer.score(host: host, query: "zzz",  tagName: "Production") == 0)
    }

    @Test func shorterPrefixMatchScoresHigher() {
        // Closer prefix → smaller (alias.count - query.count) → higher bonus.
        let close = SSHHost(aliases: ["proda"])     // "prod" + 1 char
        let far   = SSHHost(aliases: ["production"]) // "prod" + 6 chars
        #expect(HostSearchScorer.score(host: close, query: "prod") >
                HostSearchScorer.score(host: far,   query: "prod"))
    }

    @Test func scoreIsCaseInsensitive() {
        let host = SSHHost(aliases: ["MyServer"])
        #expect(HostSearchScorer.score(host: host, query: "myserver") == 1000)
    }

    @Test func portMatchedAsString() {
        let host = SSHHost(aliases: ["server"], port: 2222)
        #expect(HostSearchScorer.score(host: host, query: "2222") > 0)
    }
}
