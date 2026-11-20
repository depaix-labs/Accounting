import Accounting
import AccountingCompiler
import Foundation
import TestFlows

extension AccountingTestFlowsSuite {
    static var entryResolutionFlow: TestFlow {
        TestFlow(
            "accounting-entry-resolution",
            tags: [
                "accounting",
                "entries",
                "resolution",
            ]
        ) {
            Step("resolves parsed entries through entity account and transaction stores") {
                let resolved = try ECModelFixtures.resolveEntries(
                    ECModelFixtures.validResolutionEntrySource
                )

                try Expect.equal(
                    resolved.count,
                    2,
                    "resolved entry count"
                )

                try Expect.equal(
                    resolved[0].id ?? -1,
                    9201,
                    "first resolved entry id"
                )

                try Expect.equal(
                    resolved[1].id ?? -1,
                    9202,
                    "second resolved entry id"
                )

                try Expect.true(
                    resolved[0].lines.contains {
                        $0.account.code == "BLimBanRba"
                    },
                    "bank posting resolves to canonical account code"
                )

                try Expect.true(
                    resolved[1].lines.contains {
                        $0.account.code == "BLimKasKas"
                    },
                    "cash posting resolves to canonical account code"
                )

                try Expect.equal(
                    resolved[0]
                        .transactionReferences
                        .map(\.id),
                    [7301],
                    "transaction references resolve to transaction keys"
                )

                try resolved[0].assertBalancing()
                try resolved[1].assertBalancing()
            }

            Step("resolves local posting codes without losing their separate identity") {
                let chart = try CompiledChart(
                    name: "posting-binding-fixture",
                    version: .init(major: 3, minor: 8),
                    nodes: ECModelFixtures.postingNodes()
                )
                let bankA = try AccountKey("10201")
                let bankB = try AccountKey("10202")
                let catalog = try LocalAccountCatalog(
                    accounts: [
                        try LocalAccount(key: bankA, rgsIdentifier: "BLimBanRba"),
                        try LocalAccount(key: bankB, rgsIdentifier: "BLimBanRba")
                    ],
                    chart: chart
                )
                let source = """
                entry {
                    id = 9233
                    date = 2026-08-15

                    for (bank_fixture) in (10201) {
                        debit = 1.00
                    }
                    for (bank_fixture) in (10202) {
                        debit = 2.00
                    }
                    for (revenue_fixture) in (WOmzNodOdh) {
                        credit = 3.00
                    }
                }
                """
                let entries = try ECModelFixtures.parseEntries(source)
                let store = try AccountStore(chart: chart)
                let resolved = try EntryResolutionPass.resolve(
                    entries,
                    entities: ECModelFixtures.semanticEntityStore(),
                    accounts: store,
                    transactions: ECModelFixtures.semanticTransactionStore(),
                    settings: ECModelFixtures.parseSettings(),
                    localAccounts: catalog
                )
                try Expect.equal(resolved.count, 1, "one entry resolved")
                let lines = resolved[0].lines
                try Expect.equal(
                    lines.map(\.account.code),
                    ["BLimBanRba", "BLimBanRba", "WOmzNodOdh"],
                    "existing RGS classification survives local-account resolution"
                )
                try Expect.equal(
                    lines.map { $0.localAccount?.code },
                    ["10201", "10202", nil],
                    "distinct project-local identities survive resolution"
                )
                try Expect.equal(
                    trialBalance(resolved).first { $0.accountCode == "BLimBanRba" }?.debit,
                    Decimal(3),
                    "RGS-facing trial balance still aggregates both local accounts"
                )
                let serialized = try JSONEncoder().encode(lines[0])
                let decoded = try JSONDecoder().decode(ResolvedLine.self, from: serialized)
                try Expect.equal(
                    decoded.localAccount?.code,
                    "10201",
                    "posting identity survives Codable round-trip"
                )
                let withoutCatalog = ECModelFixtures.didThrow {
                    _ = try EntryResolutionPass.resolve(
                        entries,
                        entities: ECModelFixtures.semanticEntityStore(),
                        accounts: store,
                        transactions: ECModelFixtures.semanticTransactionStore(),
                        settings: ECModelFixtures.parseSettings()
                    )
                }
                try Expect.true(
                    withoutCatalog,
                    "local numeric codes remain unavailable unless a catalog is supplied"
                )
                let chartWithDifferentIDs = try CompiledChart(
                    name: "other-chart-fixture",
                    version: .init(major: 3, minor: 8),
                    nodes: [
                        try ECModelFixtures.makePostingNode(
                            id: 999, code: "BLimBanRba", direction: .debit
                        ),
                        try ECModelFixtures.makePostingNode(
                            id: 2, code: "BLimKasKas", direction: .debit
                        ),
                        try ECModelFixtures.makePostingNode(
                            id: 3, code: "WOmzNodOdh", direction: .credit
                        )
                    ]
                )
                let incompatible = ECModelFixtures.didThrow {
                    _ = try EntryResolutionPass.resolve(
                        entries,
                        entities: ECModelFixtures.semanticEntityStore(),
                        accounts: AccountStore(chart: chartWithDifferentIDs),
                        transactions: ECModelFixtures.semanticTransactionStore(),
                        settings: ECModelFixtures.parseSettings(),
                        localAccounts: catalog
                    )
                }
                try Expect.true(incompatible, "catalog and active RGS chart cannot disagree")
            }

            Step("classifies RGS identifiers distinctly from numeric codes and paths") {
                let canonical = try ECModelFixtures.parseEntries(
                    ECModelFixtures.validResolutionEntrySource
                )
                try Expect.equal(
                    canonical.flatMap(\.lines).map(\.account),
                    [
                        .identifier("BLimBanRba"),
                        .identifier("WOmzNodOdh"),
                        .identifier("BLimKasKas"),
                        .identifier("WOmzNodOdh"),
                    ],
                    "existing RGS posting syntax produces identifier references"
                )

                let variants = try ECModelFixtures.parseEntries(
                    """
                    entry {
                        id = 9222
                        date = 2026-08-15

                        for (bank_fixture) in (10201) { debit = 1.00 }
                        for (bank_fixture) in (assets.bank.main) { debit = 1.00 }
                        for (revenue_fixture) in (account WOmzNodOdh) { credit = 1.00 }
                        for (bank_fixture) in account(BLimBanRba) { debit = 1.00 }
                    }
                    """
                )
                try Expect.equal(
                    variants.count,
                    1,
                    "parser retains the one-entry fixture"
                )
                try Expect.equal(
                    variants[0].lines.map(\.account),
                    [
                        .code("10201"),
                        .path(["assets", "bank", "main"]),
                        .identifier("WOmzNodOdh"),
                        .identifier("BLimBanRba"),
                    ],
                    "account-reference representations follow their syntax namespaces"
                )
            }

            Step("accepts balance entity with bank account") {
                let resolved = try ECModelFixtures.resolveEntries(
                    """
                    entry {
                        id = 9220
                        date = 2026-08-15

                        for (bank_fixture) in (BLimBanRba) {
                            debit = 10.00
                        }

                        for (revenue_fixture) in (WOmzNodOdh) {
                            credit = 10.00
                        }
                    }
                    """
                )

                try Expect.equal(
                    resolved.count,
                    1,
                    "resolved balance-bank entry"
                )
            }

            Step("accepts cash entity with cash account") {
                let resolved = try ECModelFixtures.resolveEntries(
                    """
                    entry {
                        id = 9221
                        date = 2026-08-15

                        for (cash_fixture) in (BLimKasKas) {
                            debit = 10.00
                        }

                        for (revenue_fixture) in (WOmzNodOdh) {
                            credit = 10.00
                        }
                    }
                    """
                )

                try Expect.equal(
                    resolved.count,
                    1,
                    "resolved cash-cash entry"
                )
            }

            Step("rejects cash entity with bank account") {
                let threw = ECModelFixtures.didThrow {
                    _ = try ECModelFixtures.resolveEntries(
                        ECModelFixtures.invalidCashBankEntrySource
                    )
                }

                try Expect.true(
                    threw,
                    "cash entity should not resolve against bank account"
                )
            }

            Step("rejects balance entity with cash account") {
                let threw = ECModelFixtures.didThrow {
                    _ = try ECModelFixtures.resolveEntries(
                        ECModelFixtures.invalidBalanceCashEntrySource
                    )
                }

                try Expect.true(
                    threw,
                    "balance entity should not resolve against cash account"
                )
            }

            Step("rejects unresolved entity") {
                let threw = ECModelFixtures.didThrow {
                    _ = try ECModelFixtures.resolveEntries(
                        ECModelFixtures.missingEntityEntrySource
                    )
                }

                try Expect.true(
                    threw,
                    "unknown entity should fail resolution"
                )
            }

            Step("rejects unresolved account") {
                let threw = ECModelFixtures.didThrow {
                    _ = try ECModelFixtures.resolveEntries(
                        ECModelFixtures.missingAccountEntrySource
                    )
                }

                try Expect.true(
                    threw,
                    "unknown account should fail resolution"
                )
            }

            Step("rejects unresolved transaction reference") {
                let threw = ECModelFixtures.didThrow {
                    _ = try ECModelFixtures.resolveEntries(
                        ECModelFixtures.missingTransactionEntrySource
                    )
                }

                try Expect.true(
                    threw,
                    "unknown transaction reference should fail resolution"
                )
            }
        }
    }

    static var rgsIndexFlow: TestFlow {
        TestFlow(
            "accounting-rgs-index",
            tags: [
                "accounting",
                "rgs",
                "index",
            ]
        ) {
            Step("indexes identifiers references and canonical sort keys") {
                let node = try ECModelFixtures.makeIndexedNode(
                    id: 100,
                    code: "WFixtureCanonical",
                    sortKey: "W.H.A.020",
                    reference: "REF-001"
                )

                let (
                    index,
                    _
                ) = try RGSIndex.build(
                    from: [node]
                )

                try Expect.equal(
                    index.byIdentifier["WFixtureCanonical"] ?? -1,
                    100,
                    "identifier index"
                )

                try Expect.equal(
                    index.byReference["REF-001"] ?? -1,
                    100,
                    "reference index"
                )

                try Expect.equal(
                    index.bySortKey["W.H.A020"] ?? -1,
                    100,
                    "canonical sort-key index"
                )
            }

            Step("rejects duplicate identifiers in all modes") {
                let first = try ECModelFixtures.makeIndexedNode(
                    id: 101,
                    code: "WDuplicateIdentifier",
                    sortKey: "W.A"
                )

                let second = try ECModelFixtures.makeIndexedNode(
                    id: 102,
                    code: "WDuplicateIdentifier",
                    sortKey: "W.B"
                )

                let nonStrictThrew = ECModelFixtures.didThrow {
                    _ = try RGSIndex.build(
                        from: [
                            first,
                            second,
                        ],
                        strict: false
                    )
                }

                let strictThrew = ECModelFixtures.didThrow {
                    _ = try RGSIndex.build(
                        from: [
                            first,
                            second,
                        ],
                        strict: true
                    )
                }

                try Expect.true(
                    nonStrictThrew,
                    "duplicate identifier should fail non-strict build"
                )

                try Expect.true(
                    strictThrew,
                    "duplicate identifier should fail strict build"
                )
            }

            Step("duplicate sort keys are tolerated non-strict and rejected strict") {
                let first = try ECModelFixtures.makeIndexedNode(
                    id: 103,
                    code: "WDuplicateSortOne",
                    sortKey: "W.D"
                )

                let second = try ECModelFixtures.makeIndexedNode(
                    id: 104,
                    code: "WDuplicateSortTwo",
                    sortKey: "W.D"
                )

                let (
                    index,
                    _
                ) = try RGSIndex.build(
                    from: [
                        first,
                        second,
                    ],
                    strict: false
                )

                try Expect.equal(
                    index.bySortKey["W.D"] ?? -1,
                    103,
                    "non-strict duplicate sort keeps first node"
                )

                let strictThrew = ECModelFixtures.didThrow {
                    _ = try RGSIndex.build(
                        from: [
                            first,
                            second,
                        ],
                        strict: true
                    )
                }

                try Expect.true(
                    strictThrew,
                    "strict duplicate sort should fail"
                )
            }

            Step("duplicate references are tolerated non-strict and rejected strict") {
                let first = try ECModelFixtures.makeIndexedNode(
                    id: 105,
                    code: "WDuplicateReferenceOne",
                    sortKey: "W.E",
                    reference: "REF-DUP"
                )

                let second = try ECModelFixtures.makeIndexedNode(
                    id: 106,
                    code: "WDuplicateReferenceTwo",
                    sortKey: "W.F",
                    reference: "REF-DUP"
                )

                let (
                    index,
                    _
                ) = try RGSIndex.build(
                    from: [
                        first,
                        second,
                    ],
                    strict: false
                )

                try Expect.equal(
                    index.byReference.count,
                    1,
                    "non-strict duplicate reference produces one index key"
                )
                try Expect.equal(
                    index.byReference["REF-DUP"] ?? -1,
                    105,
                    "non-strict duplicate reference keeps the first node"
                )

                let strictThrew = ECModelFixtures.didThrow {
                    _ = try RGSIndex.build(
                        from: [
                            first,
                            second,
                        ],
                        strict: true
                    )
                }

                try Expect.true(
                    strictThrew,
                    "strict duplicate reference should fail"
                )
            }

            Step("rejects duplicate numeric node IDs even with distinct identifiers") {
                let first = try ECModelFixtures.makeIndexedNode(
                    id: 107,
                    code: "WDuplicateIDOne",
                    sortKey: "W.G"
                )
                let second = try ECModelFixtures.makeIndexedNode(
                    id: 107,
                    code: "WDuplicateIDTwo",
                    sortKey: "W.H"
                )

                for strict in [false, true] {
                    let threwExpectedError: Bool
                    do {
                        _ = try RGSIndex.build(from: [first, second], strict: strict)
                        threwExpectedError = false
                    } catch CompiledChartIndexError.duplicateNodeID(
                        let id, let firstCode, let duplicateCode
                    ) {
                        threwExpectedError = id == 107
                            && firstCode == "WDuplicateIDOne"
                            && duplicateCode == "WDuplicateIDTwo"
                    } catch {
                        threwExpectedError = false
                    }
                    try Expect.true(
                        threwExpectedError,
                        "duplicate node IDs must produce a typed error in strict=\(strict)"
                    )
                }
            }

            Step("rebuilds stale serialized chart indexes from authoritative nodes") {
                let node = try ECModelFixtures.makeIndexedNode(
                    id: 108,
                    code: "WCachedIdentity",
                    sortKey: "W.I"
                )
                // The store's hierarchy gate requires the level-1 RGS parent.
                // Include it so this test isolates persisted-index reconstruction.
                let root = try ECModelFixtures.makePostingNode(
                    id: 109,
                    code: "W",
                    direction: .credit
                )
                let chart = try CompiledChart(
                    name: "cached-index-fixture",
                    version: .init(major: 3, minor: 8),
                    nodes: [root, node]
                )
                let encoded = try JSONEncoder().encode(chart)
                var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
                var cachedIndex = object["index"] as! [String: Any]
                cachedIndex["byIdentifier"] = ["WCorruptCachedIdentity": 999]
                object["index"] = cachedIndex
                let staleData = try JSONSerialization.data(withJSONObject: object)
                let decoded = try JSONDecoder().decode(CompiledChart.self, from: staleData)

                try Expect.equal(
                    decoded.index?.byIdentifier["WCachedIdentity"] ?? -1,
                    108,
                    "decoding derives a canonical index from nodes"
                )
                try Expect.true(
                    decoded.index?.byIdentifier["WCorruptCachedIdentity"] == nil,
                    "stale cached identifiers must not survive decoding"
                )
                let decodedStore = try AccountStore(chart: decoded)
                try Expect.equal(
                    try decodedStore.resolve(.identifier("WCachedIdentity"), at: nil).id,
                    108,
                    "chart-backed AccountStore uses the corrected identifier mapping"
                )

                object.removeValue(forKey: "index")
                let noCacheData = try JSONSerialization.data(withJSONObject: object)
                let noCache = try JSONDecoder().decode(CompiledChart.self, from: noCacheData)
                try Expect.equal(
                    noCache.index?.byIdentifier["WCachedIdentity"] ?? -1,
                    108,
                    "legacy charts without cached indexes remain supported"
                )
            }

            Step("AccountStore validates identity and preserves lookup boundaries") {
                let node = try ECModelFixtures.makePostingNode(
                    id: 121,
                    code: "WAccountStoreIdentity",
                    direction: .credit
                )
                let chart = try CompiledChart(
                    name: "account-store-identity-fixture",
                    version: .init(major: 3, minor: 8),
                    nodes: [node]
                )
                let indexed = try AccountStore(chart: chart)
                let nodesOnly = try AccountStore(nodes: [node])

                try Expect.equal(
                    try indexed.resolve(.code("WAccountStoreIdentity"), at: nil).id,
                    121,
                    "chart posting-code lookup"
                )
                try Expect.equal(
                    try indexed.resolve(.identifier("WAccountStoreIdentity"), at: nil).id,
                    121,
                    "chart RGS-identifier lookup"
                )
                try Expect.equal(
                    try indexed.resolve(.path(["WAccountStoreIdentity"]), at: nil).id,
                    121,
                    "legacy single-segment path lookup"
                )
                try Expect.equal(
                    try nodesOnly.resolve(.code("WAccountStoreIdentity"), at: nil).id,
                    121,
                    "nodes-only posting-code lookup"
                )
                try Expect.true(
                    ECModelFixtures.didThrow {
                        _ = try nodesOnly.resolve(.identifier("WAccountStoreIdentity"), at: nil)
                    },
                    "nodes-only stores must not imply identifier-index availability"
                )

                let duplicateID = try ECModelFixtures.makePostingNode(
                    id: 121,
                    code: "WAccountStoreDuplicateID",
                    direction: .credit
                )
                let typedDuplicateID: Bool
                do {
                    _ = try AccountStore(nodes: [node, duplicateID])
                    typedDuplicateID = false
                } catch CompiledChartIndexError.duplicateNodeID(let id, _, _) {
                    typedDuplicateID = id == 121
                } catch {
                    typedDuplicateID = false
                }
                try Expect.true(
                    typedDuplicateID,
                    "nodes-only stores must reject duplicate numeric node IDs"
                )
            }

            Step("keeps local account identities distinct from RGS taxonomy bindings") {
                let node = try ECModelFixtures.makePostingNode(
                    id: 131,
                    code: "BLimBanRba",
                    direction: .debit
                )
                let chart = try CompiledChart(
                    name: "local-account-contract-fixture",
                    version: .init(major: 3, minor: 8),
                    nodes: [node]
                )
                let firstKey = try AccountKey("10201")
                let secondKey = try AccountKey("10202")
                let first = try LocalAccount(
                    key: firstKey,
                    rgsIdentifier: "BLimBanRba",
                    label: "Main bank"
                )
                let second = try LocalAccount(
                    key: secondKey,
                    rgsIdentifier: "BLimBanRba"
                )
                let catalog = try LocalAccountCatalog(
                    accounts: [first, second],
                    chart: chart
                )
                try Expect.equal(
                    catalog.count,
                    2,
                    "two local identities can bind to one RGS concept"
                )
                try Expect.equal(
                    catalog.account(for: firstKey)?.label,
                    "Main bank",
                    "local presentation metadata survives binding"
                )
                try Expect.equal(
                    catalog.rgsNode(for: firstKey)?.id,
                    131,
                    "first local code resolves to the RGS concept"
                )
                try Expect.equal(
                    catalog.rgsNode(for: secondKey)?.id,
                    131,
                    "second local code resolves independently to the same RGS concept"
                )

                let duplicateRejected: Bool
                do {
                    _ = try LocalAccountCatalog(accounts: [first, first], chart: chart)
                    duplicateRejected = false
                } catch LocalAccountError.duplicateCode(let code) {
                    duplicateRejected = code == "10201"
                } catch {
                    duplicateRejected = false
                }
                try Expect.true(duplicateRejected, "duplicate local identities are rejected")

                let unknownRejected: Bool
                do {
                    let unknown = try LocalAccount(
                        key: firstKey, rgsIdentifier: "BUnknownRGS"
                    )
                    _ = try LocalAccountCatalog(accounts: [unknown], chart: chart)
                    unknownRejected = false
                } catch LocalAccountError.unknownRGSIdentifier(let code, let identifier) {
                    unknownRejected = code == "10201" && identifier == "BUnknownRGS"
                } catch {
                    unknownRejected = false
                }
                try Expect.true(unknownRejected, "missing RGS binding produces a typed error")

                try Expect.true(
                    ECModelFixtures.didThrow {
                        _ = try LocalAccount(key: firstKey, rgsIdentifier: " ")
                    },
                    "local account cannot have a blank RGS target"
                )
                let malformed = Data(#"{"key":{"code":"10201"},"rgsIdentifier":""}"#.utf8)
                try Expect.true(
                    ECModelFixtures.didThrow {
                        _ = try JSONDecoder().decode(LocalAccount.self, from: malformed)
                    },
                    "Codable cannot bypass local-account binding invariants"
                )

                let nonPostable = try RGSNode(
                    id: 132,
                    codes: .init(code: "BLim"),
                    labels: .init(short: "Liquid assets", long: "Liquid assets"),
                    direction: nil,
                    level: 1,
                    temporality: .instant,
                    side: .balance
                )
                let nonPostableChart = try CompiledChart(
                    name: "non-postable-local-account-fixture",
                    version: .init(major: 3, minor: 8),
                    nodes: [nonPostable]
                )
                let nonPostableRejected: Bool
                do {
                    let account = try LocalAccount(
                        key: firstKey, rgsIdentifier: "BLim"
                    )
                    _ = try LocalAccountCatalog(
                        accounts: [account], chart: nonPostableChart
                    )
                    nonPostableRejected = false
                } catch LocalAccountError.nonPostableRGSIdentifier(let code, let identifier) {
                    nonPostableRejected = code == "10201" && identifier == "BLim"
                } catch {
                    nonPostableRejected = false
                }
                try Expect.true(nonPostableRejected, "non-postable RGS targets are rejected")

                // No implicit compiler/AccountStore installation in this pass.
                let existingStore = try AccountStore(chart: chart)
                try Expect.true(
                    ECModelFixtures.didThrow {
                        _ = try existingStore.resolve(.code("10201"), at: nil)
                    },
                    "building a catalog does not implicitly install local codes"
                )
            }

            Step("enriches an already indexed chart on explicit request") {
                let root = try ECModelFixtures.makeIndexedNode(
                    id: 113,
                    code: "WIndexedRoot",
                    sortKey: "W"
                )
                let child = try ECModelFixtures.makeIndexedNode(
                    id: 114,
                    code: "WIndexedChild",
                    sortKey: "W.J"
                )
                let chart = try CompiledChart(
                    name: "indexed-enrichment-fixture",
                    version: .init(major: 3, minor: 8),
                    nodes: [root, child]
                )
                try Expect.true(
                    chart.nodes.first { $0.id == 114 }?.xlsx?.links.parentId == nil,
                    "initial indexed chart has no resolved parent"
                )
                let enriched = try chart.ensuringIndex(enrichNodes: true, strict: true)
                try Expect.equal(
                    enriched.nodes.first { $0.id == 114 }?.xlsx?.links.parentId ?? -1,
                    113,
                    "explicit enrichment must run despite a cached index"
                )
            }

            Step("enrichment resolves parent and level-two ids") {
                let root = try ECModelFixtures.makeIndexedNode(
                    id: 110,
                    code: "WHierarchyRoot",
                    sortKey: "W"
                )

                let levelTwo = try ECModelFixtures.makeIndexedNode(
                    id: 111,
                    code: "WHierarchyLevelTwo",
                    sortKey: "W.A"
                )

                let leaf = try ECModelFixtures.makeIndexedNode(
                    id: 112,
                    code: "WHierarchyLeaf",
                    sortKey: "W.A.B"
                )

                let (
                    _,
                    enriched
                ) = try RGSIndex.build(
                    from: [
                        root,
                        levelTwo,
                        leaf,
                    ],
                    enrichNodes: true,
                    strict: true
                )

                let nodes = enriched ?? []

                let levelTwoResolved = nodes.first {
                    $0.id == 111
                }

                let leafResolved = nodes.first {
                    $0.id == 112
                }

                try Expect.equal(
                    levelTwoResolved?
                        .xlsx?
                        .links
                        .parentId ?? -1,
                    110,
                    "level-two parent id"
                )

                try Expect.equal(
                    leafResolved?
                        .xlsx?
                        .links
                        .parentId ?? -1,
                    111,
                    "leaf parent id"
                )

                try Expect.equal(
                    leafResolved?
                        .xlsx?
                        .links
                        .l2Id ?? -1,
                    111,
                    "leaf level-two id"
                )
            }

            Step("strict enrichment rejects missing hierarchy key") {
                let orphan = try ECModelFixtures.makeIndexedNode(
                    id: 120,
                    code: "WOrphanFixture",
                    sortKey: "W.M.O"
                )

                let threw = ECModelFixtures.didThrow {
                    _ = try RGSIndex.build(
                        from: [orphan],
                        enrichNodes: true,
                        strict: true
                    )
                }

                try Expect.true(
                    threw,
                    "strict hierarchy enrichment should reject missing parent"
                )
            }
        }
    }

    static var canonicalRootsFlow: TestFlow {
        TestFlow(
            "accounting-canonical-roots",
            tags: [
                "accounting",
                "configuration",
                "rgs",
            ]
        ) {
            Step("VOF auto-close and capital roots remain canonical") {
                let roots = BusinessEntity.vof.canonicalRoots

                try Expect.equal(
                    roots.autoCloseTargets.netIncomeCode,
                    "WNerKapKap",
                    "net income target"
                )

                try Expect.equal(
                    roots.autoCloseTargets.retainedEarningsCode,
                    "BEivKapOndAow",
                    "retained earnings target"
                )

                try Expect.equal(
                    roots.capital.profitShareCode,
                    "BEivKapOndAow",
                    "profit-share target"
                )

                try Expect.equal(
                    roots.capital.contributionRootCode,
                    "BEivKapPrs",
                    "capital contribution root"
                )

                try Expect.equal(
                    roots.capital.drawingRootCode,
                    "BEivKapPro",
                    "capital drawing root"
                )

                try Expect.equal(
                    roots.capital.equityTotalFallbackCode ?? "",
                    "BEivKap",
                    "equity fallback root"
                )
            }

            Step("VOF opening and analytics roots remain canonical") {
                let roots = BusinessEntity.vof.canonicalRoots

                try Expect.equal(
                    roots.periodOpeningRouting.equityAnchorCode,
                    "BEiv",
                    "opening equity anchor"
                )

                try Expect.equal(
                    roots.periodOpeningRouting.equityOpeningCode ?? "",
                    "BEivKapOndBeg",
                    "opening equity account"
                )

                try Expect.equal(
                    roots.periodOpeningRouting.exceptionKeepLeafAnchors,
                    ["BLim"],
                    "opening leaf exceptions"
                )

                try Expect.equal(
                    roots.analytics.netTurnoverCode,
                    "WOmz",
                    "net turnover root"
                )

                try Expect.equal(
                    roots.analytics.costOfRevenueCode,
                    "WKpr",
                    "cost-of-revenue root"
                )

                try Expect.equal(
                    roots.analytics.operatingExpensesCode,
                    "WBed",
                    "operating-expense root"
                )

                try Expect.equal(
                    roots.analytics.depreciationExpensesCode,
                    "WAfs",
                    "depreciation root"
                )

                try Expect.equal(
                    roots.analytics.financialResultCode,
                    "WFbe",
                    "financial-result root"
                )

                try Expect.equal(
                    roots.analytics.liquidAssetsCodes,
                    ["BLim"],
                    "liquid-assets roots"
                )
            }

            Step("VOF VAT roots remain canonical") {
                let vat = BusinessEntity.vof.vatRoots

                try Expect.equal(
                    vat.payableCodes,
                    [
                        "BSchBepBtw",
                        "BSchBepEob",
                        "BSchBepBaf",
                    ],
                    "VAT payable roots"
                )

                try Expect.equal(
                    vat.receivableCodes,
                    [
                        "BVorVbkTvo",
                        "BVorVbkEob",
                    ],
                    "VAT receivable roots"
                )

                try Expect.equal(
                    vat.outputCodes,
                    [
                        "BSchBepBtwOla",
                        "BSchBepEob",
                        "BSchBepBaf",
                    ],
                    "VAT output roots"
                )

                try Expect.equal(
                    vat.deductibleCodes,
                    [
                        "BSchBepBtwVoo",
                    ],
                    "VAT deductible roots"
                )

                try Expect.equal(
                    vat.privateUseCodes,
                    [
                        "BSchBepBtwOop",
                    ],
                    "VAT private-use roots"
                )
            }
        }
    }

    static var compilerFixtureFlow: TestFlow {
        TestFlow(
            "accounting-compiler-fixture",
            tags: [
                "accounting",
                "compiler",
                "integration",
            ]
        ) {
            Step("compiles a complete synthetic project") {
                let root = try ECModelFixtures.makeCompilerProjectFixture()

                defer {
                    try? FileManager.default.removeItem(
                        at: root
                    )
                }

                let result = try EntryCompileDriver.compile(
                    projectRoot: root,
                    verbose: false
                )

                try Expect.equal(
                    result.entities.byFull.count,
                    1,
                    "compiled entity count"
                )

                try Expect.equal(
                    result.accounts.byCode.count,
                    3,
                    "compiled account count"
                )

                try Expect.equal(
                    result.transactions.count,
                    1,
                    "compiled transaction count"
                )

                try Expect.equal(
                    result.entries.count,
                    1,
                    "parsed entry count"
                )

                try Expect.equal(
                    result.resolved.count,
                    1,
                    "resolved entry count"
                )

                let entry = result.resolved[0]

                try Expect.equal(
                    entry.id ?? -1,
                    9401,
                    "compiled entry id"
                )

                try Expect.equal(
                    entry.transactionReferences.map(\.id),
                    [7401],
                    "compiled transaction reference"
                )

                try Expect.true(
                    entry.lines.contains {
                        $0.account.code == "BLimBanRba"
                    },
                    "compiled bank posting"
                )

                try Expect.true(
                    entry.lines.contains {
                        $0.account.code == "WOmzNodOdh"
                    },
                    "compiled revenue posting"
                )

                try entry.assertBalancing()
            }
        }
    }
}
