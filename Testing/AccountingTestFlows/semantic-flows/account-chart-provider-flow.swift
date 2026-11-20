import Accounting
import AccountingCompiler
import Foundation
import TestFlows

private struct ChartFixtureNode: Sendable {
    let code: String
    let category: AccountCategory?
    let postable: Bool
    let sourceLabel: String
}

private struct ChartFixtureSource: Sendable {
    let name: String
    let nodes: [ChartFixtureNode]
    let parents: [AccountKey: AccountKey]
}

private struct ChartFixtureProvider: AccountChartProvider {
    func nodes(in source: ChartFixtureSource) -> [ChartFixtureNode] {
        source.nodes
    }

    func key(of node: ChartFixtureNode) throws -> AccountKey {
        try AccountKey(node.code)
    }

    func parents(in source: ChartFixtureSource) throws -> [AccountKey: AccountKey] {
        source.parents
    }

    func category(of node: ChartFixtureNode) -> AccountCategory? {
        node.category
    }

    func isPostable(_ node: ChartFixtureNode) -> Bool {
        node.postable
    }
}

private func makeRGSProviderFixtureNode(
    id: Int,
    code: String,
    level: UInt8,
    direction: Direction? = nil
) throws -> RGSNode {
    try RGSNode(
        id: id,
        codes: .init(code: code),
        labels: .init(short: code, long: code),
        direction: direction,
        level: level,
        temporality: .instant,
        side: .balance
    )
}

extension AccountingTestFlowsSuite {
    static var accountChartProviderFlow: TestFlow {
        TestFlow("accounting-chart-provider", tags: ["accounting", "chart", "invariance"]) {
            Step("retains native source and derives chart structure") {
                let root = try AccountKey("assets")
                let cash = try AccountKey("00100")
                let source = ChartFixtureSource(
                    name: "local-source-with-metadata",
                    nodes: [
                        .init(code: "assets", category: .assets, postable: false, sourceLabel: "Native root"),
                        .init(code: "00100", category: .assets, postable: true, sourceLabel: "Native bank label")
                    ],
                    parents: [cash: root]
                )
                let chart = try ChartFixtureProvider().compile(source)
                try Expect.equal(chart.count, 2, "two native nodes indexed")
                try Expect.equal(chart.source.name, source.name, "source metadata retained")
                try Expect.equal(chart.node(for: cash)?.sourceLabel, "Native bank label", "native node retained")
                try Expect.equal(chart.parent(of: cash), root, "native hierarchy retained")
                try Expect.equal(chart.category(of: cash), .assets, "category derived")
                try Expect.equal(chart.isPostable(cash), true, "postability derived")
                try Expect.equal(AccountCategory.assets.temporality, .instant, "category temporality")
                try Expect.equal(AccountCategory.revenue.temporality, .duration, "revenue temporality")
                try Expect.equal(AccountCategory.dividends.temporality, .duration, "dividends temporality")
            }

            Step("adapts native RGS hierarchy without losing native account identity") {
                let source = try CompiledChart(
                    name: "rgs-provider-fixture",
                    version: .init(major: 3, minor: 8),
                    nodes: [
                        try makeRGSProviderFixtureNode(id: 901, code: "B", level: 1),
                        try makeRGSProviderFixtureNode(id: 902, code: "BLim", level: 2),
                        try makeRGSProviderFixtureNode(
                            id: 903,
                            code: "BLimBan",
                            level: 3,
                            direction: .debit
                        )
                    ]
                )

                let provider = RGSChartProvider()
                let chart = try provider.compile(source)
                let root = try AccountKey("B")
                let group = try AccountKey("BLim")
                let leaf = try AccountKey("BLimBan")

                try Expect.equal(chart.count, 3, "all native nodes retained")
                try Expect.equal(chart.parent(of: group), root, "RGS identifier group parent")
                try Expect.equal(chart.parent(of: leaf), group, "RGS identifier leaf parent")
                try Expect.equal(chart.node(for: leaf)?.id, 903, "original RGS node retained")
                try Expect.equal(chart.isPostable(root), false, "header is nonpostable")
                try Expect.equal(chart.isPostable(leaf), true, "leaf is postable")
                try Expect.equal(chart.category(of: leaf), nil, "no guessed DEALER category")
                try Expect.equal(chart.source.nodes.count, source.nodes.count, "source chart retained")
            }

            Step("rejects ambiguous RGS parents instead of selecting one silently") {
                let source = try CompiledChart(
                    name: "ambiguous-rgs-fixture",
                    version: .init(major: 3, minor: 8),
                    nodes: [
                        try makeRGSProviderFixtureNode(id: 911, code: "B", level: 1),
                        try makeRGSProviderFixtureNode(id: 912, code: "BL", level: 1),
                        try makeRGSProviderFixtureNode(id: 913, code: "BLim", level: 2)
                    ]
                )

                try Expect.throwsError("ambiguous RGS hierarchy") {
                    _ = try RGSChartProvider().compile(source)
                }
            }

            Step("exposes sorting diagnostics explicitly without constructor output") {
                let node = try ECModelFixtures.makeIndexedNode(
                    id: 920,
                    code: "WSortingFixture",
                    sortKey: "W.A"
                )
                let reports = RGSHierarchyDiagnostics.sortingLevelReports(for: [node])

                try Expect.equal(reports.count, 1, "one derived sorting-level report")
                try Expect.true(
                    reports[0].contains("WSortingFixture"),
                    "report identifies its native RGS node"
                )
                try Expect.equal(
                    RGSHierarchyDiagnostics.sortingLevelReports(
                        for: [try makeRGSProviderFixtureNode(id: 921, code: "B", level: 1)]
                    ).count,
                    0,
                    "nodes without XLSX metadata have no sorting-level report"
                )
            }

            Step("constructs only posting-eligible accounts") {
                let root = try AccountKey("assets")
                let cash = try AccountKey("00100")
                let missing = try AccountKey("missing")
                let source = ChartFixtureSource(
                    name: "posting-eligibility",
                    nodes: [
                        .init(code: "assets", category: .assets, postable: false, sourceLabel: "Root"),
                        .init(code: "00100", category: .assets, postable: true, sourceLabel: "Cash")
                    ],
                    parents: [cash: root]
                )
                let chart = try ChartFixtureProvider().compile(source)
                let postingAccount = try chart.postingAccount(for: cash)

                try Expect.equal(postingAccount.key, cash, "valid account identity retained")
                try Expect.throwsError("nonpostable root") {
                    _ = try chart.postingAccount(for: root)
                }
                try Expect.throwsError("unknown account") {
                    _ = try chart.postingAccount(for: missing)
                }
            }

            Step("rolls up signed amounts without losing contribution origins") {
                let root = try AccountKey("assets")
                let cash = try AccountKey("00100")
                let bank = try AccountKey("00200")
                let source = ChartFixtureSource(
                    name: "rollup-provenance",
                    nodes: [
                        .init(code: "assets", category: .assets, postable: false, sourceLabel: "Assets"),
                        .init(code: "00100", category: .assets, postable: true, sourceLabel: "Cash"),
                        .init(code: "00200", category: .assets, postable: true, sourceLabel: "Bank")
                    ],
                    parents: [cash: root, bank: root]
                )
                let chart = try ChartFixtureProvider().compile(source)
                let cashAccount = try chart.postingAccount(for: cash)
                let bankAccount = try chart.postingAccount(for: bank)

                let postings: [AccountPosting<ChartFixtureProvider, String>] = [
                    .init(account: cashAccount, amount: Decimal(100), origin: "cash-debit"),
                    .init(account: cashAccount, amount: Decimal(-30), origin: "cash-credit"),
                    .init(account: bankAccount, amount: Decimal(25), origin: "bank-debit")
                ]
                let result = try chart.rollup(postings)

                try Expect.equal(result.totalsByAccount[cash], Decimal(70), "cash net total")
                try Expect.equal(result.totalsByAccount[bank], Decimal(25), "bank net total")
                try Expect.equal(result.totalsByAccount[root], Decimal(95), "ancestor total")
                try Expect.equal(result.postings.count, 3, "original contribution count")
                try Expect.equal(
                    result.postings(for: cash).map(\.origin),
                    ["cash-debit", "cash-credit"],
                    "cash retains both signed sources"
                )
                try Expect.equal(
                    result.postings(for: root).map(\.origin),
                    ["cash-debit", "cash-credit", "bank-debit"],
                    "ancestor retains original posting order and sources"
                )
                try Expect.equal(
                    result.postings(for: root).map(\.amount),
                    [Decimal(100), Decimal(-30), Decimal(25)],
                    "original signed amounts remain inspectable"
                )
            }

            Step("rejects posting targets from incompatible chart instances") {
                let key = try AccountKey("00100")
                let first = try ChartFixtureProvider().compile(
                    ChartFixtureSource(
                        name: "first-chart",
                        nodes: [
                            .init(code: "00100", category: .assets, postable: true, sourceLabel: "Cash")
                        ],
                        parents: [:]
                    )
                )
                let second = try ChartFixtureProvider().compile(
                    ChartFixtureSource(
                        name: "second-chart",
                        nodes: [
                            .init(code: "00100", category: .assets, postable: false, sourceLabel: "Header")
                        ],
                        parents: [:]
                    )
                )
                let posting = AccountPosting(
                    account: try first.postingAccount(for: key),
                    amount: Decimal(10),
                    origin: "first-chart-source"
                )

                try Expect.throwsError("postability revalidated against destination chart") {
                    _ = try second.rollup([posting])
                }
            }

            Step("rejects duplicate keys, missing parents and cycles") {
                let a = try AccountKey("a")
                let b = try AccountKey("b")
                let provider = ChartFixtureProvider()
                let nodes = [
                    ChartFixtureNode(code: "a", category: nil, postable: false, sourceLabel: "A"),
                    ChartFixtureNode(code: "b", category: nil, postable: true, sourceLabel: "B")
                ]
                try Expect.throwsError("duplicate key") {
                    _ = try provider.compile(.init(name: "duplicates", nodes: [nodes[0], nodes[0]], parents: [:]))
                }
                try Expect.throwsError("missing parent") {
                    _ = try provider.compile(.init(name: "missing-parent", nodes: nodes, parents: [b: try AccountKey("missing")]))
                }
                try Expect.throwsError("cycle") {
                    _ = try provider.compile(.init(name: "cycle", nodes: nodes, parents: [a: b, b: a]))
                }
            }
        }
    }
}
