import Foundation
import AccountingV2
import TestFlows

private func makeV2BalanceEntry(
    id: Int,
    amount: Decimal,
    owner: Entity.Reference,
    bank: Account.Reference,
    revenue: Account.Reference,
    chart: Chart,
    entities: Entities
) throws -> Entry {
    let debit = try Entry.Line(.init(
        account: bank,
        entity: owner,
        direction: .debit,
        amount: amount,
        chart: chart,
        entities: entities
    ))
    let credit = try Entry.Line(.init(
        account: revenue,
        entity: owner,
        direction: .credit,
        amount: amount,
        chart: chart,
        entities: entities
    ))
    return try Entry(.init(
        id: Entry.ID(id),
        date: Date(timeIntervalSince1970: 0),
        lines: [debit, credit]
    ))
}

extension AccountingTestFlowsSuite {
    static var accountingV2BalancesFlow: TestFlow {
        TestFlow("accounting-v2-balances", tags: ["accounting", "v2", "balances"]) {
            Step("distinguishes direct and hierarchical signed amounts") {
                let fixture = try V2JournalFixture()
                let first = try fixture.entry(id: 1, amount: 100)
                let second = try fixture.entry(id: 2, amount: 250)
                let journal = try Journal(.init(
                    entries: [first, second],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))
                let balances = Balances(.init(ledger: ledger))
                let balanceRoot = try Account.Reference("B")
                let incomeRoot = try Account.Reference("W")

                try Expect.equal(
                    balances.amount(for: fixture.bank)?.posted ?? -1,
                    350,
                    "direct debit total"
                )
                try Expect.equal(
                    balances.amount(for: fixture.revenue)?.posted ?? 1,
                    -350,
                    "direct credit total retains its sign"
                )
                try Expect.equal(
                    balances.amount(for: balanceRoot)?.posted ?? -1,
                    0,
                    "non-postable root has no direct postings"
                )
                try Expect.equal(
                    balances.amount(for: balanceRoot)?.total ?? -1,
                    350,
                    "balance root includes its descendants"
                )
                try Expect.equal(
                    balances.amount(for: incomeRoot)?.total ?? 1,
                    -350,
                    "income root preserves debit-minus-credit convention"
                )
                try Expect.equal(
                    balances.amount(for: fixture.bank)?.total ?? -1,
                    350,
                    "leaf total equals direct total"
                )
                try Expect.equal(
                    balances.amount(for: balanceRoot)?.descendants ?? -1,
                    350,
                    "root has descendant-only contributions"
                )
                try Expect.equal(
                    balances.amount(for: fixture.bank)?.descendants ?? -1,
                    0,
                    "leaf has no descendant contributions"
                )
                try Expect.equal(
                    ledger.postings.reduce(Decimal.zero) { $0 + $1.signedAmount },
                    0,
                    "balanced source remains balanced"
                )
            }

            Step("retains original contributing postings without synthetic lines") {
                let fixture = try V2JournalFixture()
                let second = try fixture.entry(id: 2, amount: 250)
                let first = try fixture.entry(id: 1, amount: 100)
                let journal = try Journal(.init(
                    entries: [second, first],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))
                let balances = Balances(.init(ledger: ledger))
                let balanceRoot = try Account.Reference("B")
                let incomeRoot = try Account.Reference("W")

                let debitContributions = balances.contributingPostings(to: balanceRoot) ?? []
                let creditContributions = balances.contributingPostings(to: incomeRoot) ?? []

                try Expect.equal(
                    debitContributions.map(\.source.entryID.value),
                    [2, 1],
                    "original entry order"
                )
                try Expect.equal(
                    debitContributions.map(\.source.lineIndex),
                    [0, 0],
                    "original debit-line coordinates"
                )
                try Expect.equal(
                    creditContributions.map(\.source.lineIndex),
                    [1, 1],
                    "original credit-line coordinates"
                )
                try Expect.equal(
                    debitContributions.map(\.amount),
                    [250, 100],
                    "original magnitudes retained"
                )
                try Expect.equal(
                    balances.ledger.postings.count,
                    ledger.postings.count,
                    "rollup does not change posting count"
                )
                try Expect.equal(
                    ledger.postings(for: balanceRoot).count,
                    0,
                    "ledger remains free of ancestor postings"
                )
            }

            Step("separates entity totals without changing global totals") {
                let fixture = try V2JournalFixture()
                let secondOwner = try Entity.Reference(
                    class: "person",
                    family: "owner",
                    alias: Entity.Alias(name: "owner-b")
                )
                let entities = try Entities([
                    Entity(.init(reference: fixture.owner)),
                    Entity(.init(reference: secondOwner))
                ])

                let first = try makeV2BalanceEntry(
                    id: 1,
                    amount: 100,
                    owner: fixture.owner,
                    bank: fixture.bank,
                    revenue: fixture.revenue,
                    chart: fixture.chart,
                    entities: entities
                )
                let second = try makeV2BalanceEntry(
                    id: 2,
                    amount: 50,
                    owner: secondOwner,
                    bank: fixture.bank,
                    revenue: fixture.revenue,
                    chart: fixture.chart,
                    entities: entities
                )
                let journal = try Journal(.init(
                    entries: [first, second],
                    chart: fixture.chart,
                    entities: entities
                ))
                let balances = Balances(.init(ledger: try Ledger(.init(journal: journal))))
                let balanceRoot = try Account.Reference("B")
                let incomeRoot = try Account.Reference("W")

                try Expect.equal(
                    balances.amount(for: fixture.bank)?.posted ?? -1,
                    150,
                    "combined direct total"
                )
                try Expect.equal(
                    balances.amount(for: fixture.bank, entity: fixture.owner)?.posted ?? -1,
                    100,
                    "first owner direct total"
                )
                try Expect.equal(
                    balances.amount(for: fixture.bank, entity: secondOwner)?.posted ?? -1,
                    50,
                    "second owner direct total"
                )
                try Expect.equal(
                    balances.amount(for: balanceRoot, entity: fixture.owner)?.total ?? -1,
                    100,
                    "first owner ancestor total"
                )
                try Expect.equal(
                    balances.amount(for: balanceRoot, entity: secondOwner)?.total ?? -1,
                    50,
                    "second owner ancestor total"
                )
                try Expect.equal(
                    balances.amount(for: incomeRoot, entity: secondOwner)?.total ?? 1,
                    -50,
                    "second owner credit-side total"
                )
                try Expect.equal(
                    balances.contributingPostings(to: balanceRoot, entity: secondOwner)?.count ?? -1,
                    1,
                    "entity-specific source contributions"
                )
                try Expect.equal(
                    balances.contributingPostings(to: balanceRoot)?.count ?? -1,
                    2,
                    "global source contributions"
                )
            }

            Step("preserves zero-net posting history") {
                let fixture = try V2JournalFixture()
                let first = try fixture.entry(id: 1, amount: 100)
                let reversing = try Entry(.init(
                    id: Entry.ID(2),
                    date: Date(timeIntervalSince1970: 0),
                    lines: [
                        fixture.line(account: fixture.bank, direction: .credit, amount: 100),
                        fixture.line(account: fixture.revenue, direction: .debit, amount: 100)
                    ]
                ))
                let journal = try Journal(.init(
                    entries: [first, reversing],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let balances = Balances(.init(ledger: try Ledger(.init(journal: journal))))
                let amount = balances.amount(for: fixture.bank)

                try Expect.equal(amount?.posted ?? -1, 0, "signed postings cancel")
                try Expect.equal(amount?.total ?? -1, 0, "leaf total cancels")
                try Expect.equal(amount?.descendants ?? -1, 0, "leaf has no descendants")
                try Expect.equal(
                    balances.ledger.postings(for: fixture.bank).count,
                    2,
                    "zero net does not mean no postings"
                )
            }

            Step("distinguishes unknown references from valid zero balances") {
                let fixture = try V2JournalFixture()
                let journal = try Journal(.init(
                    entries: [],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let balances = Balances(.init(ledger: try Ledger(.init(journal: journal))))
                let validRoot = try Account.Reference("B")
                let unknownAccount = try Account.Reference("missing")
                let unknownEntity = try Entity.Reference(
                    class: "person",
                    family: "owner",
                    alias: Entity.Alias(name: "missing")
                )

                try Expect.equal(
                    balances.amount(for: validRoot)?.posted ?? -1,
                    0,
                    "known empty direct balance"
                )
                try Expect.equal(
                    balances.amount(for: validRoot)?.total ?? -1,
                    0,
                    "known empty rolled balance"
                )
                try Expect.equal(
                    balances.contributingPostings(to: validRoot)?.count ?? -1,
                    0,
                    "known empty contribution set"
                )
                try Expect.equal(
                    balances.amount(for: unknownAccount)?.posted == nil,
                    true,
                    "unknown account is not a zero account"
                )
                try Expect.equal(
                    balances.amount(for: validRoot, entity: unknownEntity)?.total == nil,
                    true,
                    "unknown entity is not a zero entity"
                )
                try Expect.equal(
                    balances.contributingPostings(to: unknownAccount) == nil,
                    true,
                    "unknown account has no valid contribution query"
                )
                try Expect.equal(
                    balances.amount(for: fixture.bank, entity: fixture.owner)?.posted ?? -1,
                    0,
                    "known entity and account without activity"
                )
            }
        }
    }
}
