import Testing
@testable import sshCMModels

// Helpers used throughout — zero-dependency stand-ins for the real stores.
// Favorite ordering is now intrinsic to the host (`SSHHost.isFavorite`), so the
// filter no longer takes an `isFavorite` closure; the tag closures key off the
// host's own `tag` rather than its alias.
private func flatRank(_: HostTag?) -> Int { 0 }
private func noTag(_: HostTag?) -> String? { nil }
private func alwaysReachable(_: SSHHost) -> Bool { true }
private func neverReachable(_: SSHHost) -> Bool { false }

@Suite("HostListFilter – sorting")
struct HostListFilterSortingTests {

    @Test func favoritesAlwaysSortFirst() {
        let hosts = [
            SSHHost(aliases: ["z-server"], hostName: "z.com"),
            SSHHost(aliases: ["a-server"], hostName: "a.com", isFavorite: false)
        ]
        var withFav = hosts
        withFav[0].isFavorite = true   // z-server is favorited
        let result = HostListFilter().apply(hosts: withFav, tagRank: flatRank,
                                            tagName: noTag, isReachable: alwaysReachable)
        #expect(result.first?.aliases.first == "z-server")
    }

    @Test func lowerTagRankSortsBefore() {
        let alpha = SSHHost(aliases: ["alpha"], tag: .red)
        let beta  = SSHHost(aliases: ["beta"], tag: .green)
        let result = HostListFilter().apply(
            hosts: [alpha, beta],
            tagRank: { $0 == .red ? 2 : 1 },   // beta (green) has lower rank → comes first
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
        let result = HostListFilter().apply(hosts: hosts, tagRank: flatRank,
                                            tagName: noTag, isReachable: alwaysReachable)
        #expect(result.map { $0.aliases.first! } == ["alice", "bob", "charlie"])
    }

    @Test func favoriteBeatsLowerTagRank() {
        let fav      = SSHHost(aliases: ["fav"],     hostName: "a.com", tag: .gray, isFavorite: true)
        let lowRank  = SSHHost(aliases: ["lowrank"], hostName: "b.com", tag: .green)
        let result = HostListFilter().apply(
            hosts: [lowRank, fav],
            tagRank: { $0 == .green ? 0 : 99 },  // lowrank wins on tag, but fav wins on favorite
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
            hosts: hosts,            tagRank: flatRank,
            tagName: noTag,
            isReachable: { $0.aliases.first == "b" }   // only "b" is reachable
        )
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "b")
    }

    @Test func showAllIncludesUnreachable() {
        let hosts = [SSHHost(aliases: ["a"]), SSHHost(aliases: ["b"])]
        let filter = HostListFilter(showOnlyReachable: false)
        let result = filter.apply(hosts: hosts, tagRank: flatRank,
                                  tagName: noTag, isReachable: neverReachable)
        #expect(result.count == 2)
    }
}

@Suite("HostListFilter – search")
struct HostListFilterSearchTests {

    @Test func emptyQueryReturnsAll() {
        let hosts = [SSHHost(aliases: ["prod"]), SSHHost(aliases: ["staging"])]
        let result = HostListFilter(searchText: "  ").apply(hosts: hosts,
                                                             tagRank: flatRank, tagName: noTag,
                                                             isReachable: alwaysReachable)
        #expect(result.count == 2)
    }

    @Test func searchMatchesPrimaryAlias() {
        let hosts = [SSHHost(aliases: ["prod-api"]), SSHHost(aliases: ["staging-api"])]
        let result = HostListFilter(searchText: "prod").apply(hosts: hosts,
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
        let result = HostListFilter(searchText: "192.168").apply(hosts: hosts,
                                                                  tagRank: flatRank, tagName: noTag,
                                                                  isReachable: alwaysReachable)
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "web")
    }

    @Test func searchMatchesSearchAliases() {
        let host = SSHHost(aliases: ["prod"], searchAliases: ["production", "live"])
        let result = HostListFilter(searchText: "live").apply(hosts: [host],
                                                               tagRank: flatRank, tagName: noTag,
                                                               isReachable: alwaysReachable)
        #expect(result.count == 1)
    }

    @Test func searchMatchesTagName() {
        let host = SSHHost(aliases: ["server"])
        let result = HostListFilter(searchText: "Produc").apply(
            hosts: [host],            tagRank: flatRank,
            tagName: { _ in "Production" },
            isReachable: alwaysReachable
        )
        #expect(result.count == 1)
    }

    @Test func searchIsCaseInsensitive() {
        let host = SSHHost(aliases: ["MyServer"])
        let result = HostListFilter(searchText: "myserver").apply(hosts: [host],
                                                                   tagRank: flatRank, tagName: noTag,
                                                                   isReachable: alwaysReachable)
        #expect(result.count == 1)
    }

    @Test func noMatchReturnsEmpty() {
        let hosts = [SSHHost(aliases: ["alpha"]), SSHHost(aliases: ["beta"])]
        let result = HostListFilter(searchText: "zzz").apply(hosts: hosts,
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
            hosts: hosts,            tagRank: flatRank,
            tagName: noTag,
            isReachable: { $0.aliases.first == "prod-web" }
        )
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "prod-web")
    }
}

@Suite("HostListFilter – zone filter")
struct HostListFilterZoneTests {

    @Test func zoneSetIncludesOnlyMemberHosts() {
        let hosts = [
            SSHHost(aliases: ["home-nas"], zone: "home"),
            SSHHost(aliases: ["work-vpn"], zone: "work"),
            SSHHost(aliases: ["no-zone"])
        ]
        let result = HostListFilter(zone: "home").apply(hosts: hosts,
                                                          tagRank: flatRank, tagName: noTag,
                                                          isReachable: alwaysReachable)
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "home-nas")
    }

    @Test func nilZoneIncludesEverything() {
        let hosts = [
            SSHHost(aliases: ["home-nas"], zone: "home"),
            SSHHost(aliases: ["no-zone"])
        ]
        let result = HostListFilter(zone: nil).apply(hosts: hosts,
                                                       tagRank: flatRank, tagName: noTag,
                                                       isReachable: alwaysReachable)
        #expect(result.count == 2)
    }

    @Test func zoneComposesWithReachability() {
        let hosts = [
            SSHHost(aliases: ["home-a"], zone: "home"),
            SSHHost(aliases: ["home-b"], zone: "home"),
            SSHHost(aliases: ["work-a"], zone: "work")
        ]
        let filter = HostListFilter(showOnlyReachable: true, zone: "home")
        let result = filter.apply(
            hosts: hosts,            tagRank: flatRank,
            tagName: noTag,
            isReachable: { $0.aliases.first == "home-a" }
        )
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "home-a")
    }

    @Test func zoneComposesWithSearchText() {
        let hosts = [
            SSHHost(aliases: ["prod-web"], zone: "aws"),
            SSHHost(aliases: ["prod-db"], zone: "home"),
            SSHHost(aliases: ["staging-web"], zone: "aws")
        ]
        let filter = HostListFilter(searchText: "prod", zone: "aws")
        let result = filter.apply(hosts: hosts, tagRank: flatRank,
                                  tagName: noTag, isReachable: alwaysReachable)
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "prod-web")
    }

    @Test func zoneReachabilityAndSearchAllCompose() {
        let hosts = [
            SSHHost(aliases: ["prod-web"], zone: "aws"),
            SSHHost(aliases: ["prod-db"], zone: "aws"),
            SSHHost(aliases: ["staging-web"], zone: "aws"),
            SSHHost(aliases: ["prod-other"], zone: "home")
        ]
        let filter = HostListFilter(searchText: "prod", showOnlyReachable: true, zone: "aws")
        let result = filter.apply(
            hosts: hosts,            tagRank: flatRank,
            tagName: noTag,
            isReachable: { $0.aliases.first == "prod-web" }
        )
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "prod-web")
    }

    @Test func zoneMatchingNoHostReturnsEmpty() {
        let hosts = [SSHHost(aliases: ["a"], zone: "home"), SSHHost(aliases: ["b"], zone: "work")]
        let result = HostListFilter(zone: "aws").apply(hosts: hosts,
                                                        tagRank: flatRank, tagName: noTag,
                                                        isReachable: alwaysReachable)
        #expect(result.isEmpty)
    }

    @Test func zoneNameMatchesInHaystackWhenNoZoneFilterSelected() {
        let hosts = [
            SSHHost(aliases: ["web"], zone: "aws"),
            SSHHost(aliases: ["db"], zone: "home")
        ]
        let result = HostListFilter(searchText: "aws").apply(hosts: hosts,
                                                              tagRank: flatRank, tagName: noTag,
                                                              isReachable: alwaysReachable)
        #expect(result.count == 1)
        #expect(result[0].aliases.first == "web")
    }

    @Test func sortingUnaffectedByZoneWhenNoZoneFilterSelected() {
        let hosts = [
            SSHHost(aliases: ["zebra"], zone: "work"),
            SSHHost(aliases: ["alpha"], zone: "home")
        ]
        let result = HostListFilter().apply(hosts: hosts, tagRank: flatRank,
                                            tagName: noTag, isReachable: alwaysReachable)
        #expect(result.map { $0.aliases.first! } == ["alpha", "zebra"])
    }
}
