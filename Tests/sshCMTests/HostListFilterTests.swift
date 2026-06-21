import Testing
@testable import sshCMModels

// Helpers used throughout — zero-dependency stand-ins for the real stores.
private func noFav(_: String) -> Bool { false }
private func oneFav(_ target: String) -> (String) -> Bool { { $0 == target } }
private func flatRank(_: String) -> Int { 0 }
private func noTag(_: String) -> String? { nil }
private func alwaysReachable(_: SSHHost) -> Bool { true }
private func neverReachable(_: SSHHost) -> Bool { false }

@Suite("HostListFilter – sorting")
struct HostListFilterSortingTests {

    @Test func favoritesAlwaysSortFirst() {
        let hosts = [
            SSHHost(aliases: ["z-server"], hostName: "z.com"),
            SSHHost(aliases: ["a-server"], hostName: "a.com")
        ]
        let filter = HostListFilter()
        let result = filter.apply(hosts: hosts, isFavorite: oneFav("z-server"),
                                  tagRank: flatRank, tagName: noTag, isReachable: alwaysReachable)
        #expect(result.first?.aliases.first == "z-server")
    }

    @Test func lowerTagRankSortsBefore() {
        let alpha = SSHHost(aliases: ["alpha"])
        let beta  = SSHHost(aliases: ["beta"])
        let filter = HostListFilter()
        let result = filter.apply(
            hosts: [alpha, beta],
            isFavorite: noFav,
            tagRank: { $0 == "alpha" ? 2 : 1 },   // beta has lower rank → comes first
            tagName: noTag,
            isReachable: alwaysReachable
        )
        #expect(result.first?.aliases.first == "beta")
    }

    @Test func alphabeticalTieBreaker() {
        let hosts = [
            SSHHost(aliases: ["charlie"]),
            SSHHost(aliases: ["alice"]),
            SSHHost(aliases: ["bob"])
        ]
        let result = HostListFilter().apply(hosts: hosts, isFavorite: noFav,
                                            tagRank: flatRank, tagName: noTag, isReachable: alwaysReachable)
        #expect(result.map { $0.aliases.first! } == ["alice", "bob", "charlie"])
    }

    @Test func favoriteBeatsLowerTagRank() {
        let fav      = SSHHost(aliases: ["fav"],     hostName: "a.com")
        let lowRank  = SSHHost(aliases: ["lowrank"], hostName: "b.com")
        let result = HostListFilter().apply(
            hosts: [lowRank, fav],
            isFavorite: oneFav("fav"),
            tagRank: { $0 == "lowrank" ? 0 : 99 },  // lowrank wins on tag, but fav wins on favorite
            tagName: noTag,
            isReachable: alwaysReachable
        )
        #expect(result.first?.aliases.first == "fav")
    }
}

@Suite("HostListFilter – reachability filter")
struct HostListFilterReachabilityTests {

    @Test func showOnlyReachableFiltersUnreachable() {
        let hosts = [SSHHost(aliases: ["a"]), SSHHost(aliases: ["b"]), SSHHost(aliases: ["c"])]
        let filter = HostListFilter(showOnlyReachable: true)
        let result = filter.apply(
            hosts: hosts,
            isFavorite: noFav,
            tagRank: flatRank,
            tagName: noTag,
            isReachable: { $0.aliases.first == "b" }   // only "b" is reachable
        )
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "b")
    }

    @Test func showAllIncludesUnreachable() {
        let hosts = [SSHHost(aliases: ["a"]), SSHHost(aliases: ["b"])]
        let filter = HostListFilter(showOnlyReachable: false)
        let result = filter.apply(hosts: hosts, isFavorite: noFav, tagRank: flatRank,
                                  tagName: noTag, isReachable: neverReachable)
        #expect(result.count == 2)
    }
}

@Suite("HostListFilter – search")
struct HostListFilterSearchTests {

    @Test func emptyQueryReturnsAll() {
        let hosts = [SSHHost(aliases: ["prod"]), SSHHost(aliases: ["staging"])]
        let result = HostListFilter(searchText: "  ").apply(hosts: hosts, isFavorite: noFav,
                                                             tagRank: flatRank, tagName: noTag,
                                                             isReachable: alwaysReachable)
        #expect(result.count == 2)
    }

    @Test func searchMatchesPrimaryAlias() {
        let hosts = [SSHHost(aliases: ["prod-api"]), SSHHost(aliases: ["staging-api"])]
        let result = HostListFilter(searchText: "prod").apply(hosts: hosts, isFavorite: noFav,
                                                              tagRank: flatRank, tagName: noTag,
                                                              isReachable: alwaysReachable)
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "prod-api")
    }

    @Test func searchMatchesHostName() {
        let hosts = [
            SSHHost(aliases: ["web"], hostName: "192.168.1.10"),
            SSHHost(aliases: ["db"],  hostName: "10.0.0.5")
        ]
        let result = HostListFilter(searchText: "192.168").apply(hosts: hosts, isFavorite: noFav,
                                                                  tagRank: flatRank, tagName: noTag,
                                                                  isReachable: alwaysReachable)
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "web")
    }

    @Test func searchMatchesSearchAliases() {
        let host = SSHHost(aliases: ["prod"], searchAliases: ["production", "live"])
        let result = HostListFilter(searchText: "live").apply(hosts: [host], isFavorite: noFav,
                                                               tagRank: flatRank, tagName: noTag,
                                                               isReachable: alwaysReachable)
        #expect(result.count == 1)
    }

    @Test func searchMatchesTagName() {
        let host = SSHHost(aliases: ["server"])
        let result = HostListFilter(searchText: "Produc").apply(
            hosts: [host],
            isFavorite: noFav,
            tagRank: flatRank,
            tagName: { _ in "Production" },
            isReachable: alwaysReachable
        )
        #expect(result.count == 1)
    }

    @Test func searchIsCaseInsensitive() {
        let host = SSHHost(aliases: ["MyServer"])
        let result = HostListFilter(searchText: "myserver").apply(hosts: [host], isFavorite: noFav,
                                                                   tagRank: flatRank, tagName: noTag,
                                                                   isReachable: alwaysReachable)
        #expect(result.count == 1)
    }

    @Test func noMatchReturnsEmpty() {
        let hosts = [SSHHost(aliases: ["alpha"]), SSHHost(aliases: ["beta"])]
        let result = HostListFilter(searchText: "zzz").apply(hosts: hosts, isFavorite: noFav,
                                                              tagRank: flatRank, tagName: noTag,
                                                              isReachable: alwaysReachable)
        #expect(result.isEmpty)
    }

    @Test func searchAndReachabilityCompose() {
        let hosts = [
            SSHHost(aliases: ["prod-web"]),
            SSHHost(aliases: ["prod-db"]),
            SSHHost(aliases: ["staging-web"])
        ]
        let filter = HostListFilter(searchText: "prod", showOnlyReachable: true)
        let result = filter.apply(
            hosts: hosts,
            isFavorite: noFav,
            tagRank: flatRank,
            tagName: noTag,
            isReachable: { $0.aliases.first == "prod-web" }
        )
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "prod-web")
    }
}
