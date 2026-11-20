import Foundation
import AccountingV2
import TestFlows

struct V2JournalFixture {
    let chart: Chart
    let entities: Entities
    let bank: Account.Reference
    let revenue: Account.Reference
    let owner: Entity.Reference

    init() throws {
        let balanceRoot = try Account(.init(code: "B", postable: false))
        let incomeRoot = try Account(.init(code: "W", postable: false))
        let bank = try Account(.init(
            code: "BLimBan", category: .assets, postable: true
        ))
        let revenue = try Account(.init(
            code: "WOmz", category: .revenue, postable: true
        ))

        self.chart = try Chart(.init(
            accounts: [balanceRoot, bank, incomeRoot, revenue],
            roots: [balanceRoot.reference, incomeRoot.reference],
            parents: [
                bank.reference: balanceRoot.reference,
                revenue.reference: incomeRoot.reference
            ],
            behavior: .init(carryforward: .identity)
        ))

        let owner = try Entity.Reference(
            class: "person",
            family: "owner",
            alias: Entity.Alias(name: "owner-a")
        )
        self.entities = try Entities([
            Entity(.init(reference: owner))
        ])
        self.bank = bank.reference
        self.revenue = revenue.reference
        self.owner = owner
    }

    func line(
        account: Account.Reference,
        direction: Direction,
        amount: Decimal
    ) throws -> Entry.Line {
        try Entry.Line(.init(
            account: account,
            entity: owner,
            direction: direction,
            amount: amount,
            chart: chart,
            entities: entities
        ))
    }

    func entry(id: Int = 1, amount: Decimal = 100) throws -> Entry {
        let debit = try line(account: bank, direction: .debit, amount: amount)
        let credit = try line(account: revenue, direction: .credit, amount: amount)
        return try Entry(.init(
            id: Entry.ID(id),
            date: Date(timeIntervalSince1970: 0),
            lines: [debit, credit]
        ))
    }
}

extension AccountingTestFlowsSuite {
    static var accountingV2JournalFlow: TestFlow {
        TestFlow("accounting-v2-journal", tags: ["accounting", "v2", "journal"]) {
            Step("line construction enforces account and entity membership") {
                let fixture = try V2JournalFixture()
                let debit = try fixture.line(
                    account: fixture.bank, direction: .debit, amount: 100
                )
                try Expect.equal(debit.account, fixture.bank, "canonical account")
                try Expect.equal(debit.entity, fixture.owner, "canonical entity")
                try Expect.equal(debit.signedAmount, 100, "debit contribution")

                let unknown = try Account.Reference("missing")
                try Expect.throwsError("unknown account") {
                    _ = try fixture.line(
                        account: unknown, direction: .debit, amount: 100
                    )
                }
                try Expect.throwsError("zero amount") {
                    _ = try fixture.line(
                        account: fixture.bank, direction: .debit, amount: 0
                    )
                }
                try Expect.throwsError("negative amount") {
                    _ = try fixture.line(
                        account: fixture.bank, direction: .debit, amount: -100
                    )
                }

                let heading = try Account.Reference("B")
                try Expect.throwsError("non-postable heading") {
                    _ = try fixture.line(
                        account: heading, direction: .debit, amount: 100
                    )
                }
                let missingEntity = try Entity.Reference(
                    class: "person",
                    family: "owner",
                    alias: Entity.Alias(name: "missing")
                )
                try Expect.throwsError("unknown entity") {
                    _ = try Entry.Line(.init(
                        account: fixture.bank,
                        entity: missingEntity,
                        direction: .debit,
                        amount: 100,
                        chart: fixture.chart,
                        entities: fixture.entities
                    ))
                }
            }

            Step("entry construction enforces identity and balanced lines") {
                let fixture = try V2JournalFixture()
                try Expect.throwsError("invalid entry ID") {
                    _ = try Entry.ID(0)
                }
                let id = try Entry.ID(1)
                let debit = try fixture.line(
                    account: fixture.bank, direction: .debit, amount: 100
                )
                let credit = try fixture.line(
                    account: fixture.revenue, direction: .credit, amount: 100
                )
                let date = Date(timeIntervalSince1970: 0)

                try Expect.throwsError("insufficient lines") {
                    _ = try Entry(.init(id: id, date: date, lines: [debit]))
                }
                try Expect.throwsError("unbalanced lines") {
                    _ = try Entry(.init(id: id, date: date, lines: [debit, debit]))
                }
                try Expect.throwsError("invalid date") {
                    _ = try Entry(.init(
                        id: id,
                        date: Date(timeIntervalSince1970: .infinity),
                        lines: [debit, credit]
                    ))
                }

                let entry = try Entry(.init(
                    id: id,
                    date: date,
                    lines: [debit, credit],
                    details: "Sale",
                    metadata: ["source": "manual"]
                ))
                try Expect.equal(entry.id, id, "entry identity")
                try Expect.equal(entry.lines.count, 2, "retained lines")
                try Expect.equal(entry.metadata["source"], "manual", "metadata")
                try Expect.equal(
                    entry.lines.reduce(Decimal.zero) { $0 + $1.signedAmount },
                    0,
                    "entry balanced"
                )
            }

            Step("journal preserves entries and rejects duplicate IDs") {
                let fixture = try V2JournalFixture()
                let first = try fixture.entry(id: 1)
                let second = try fixture.entry(id: 2)
                let journal = try Journal(.init(
                    entries: [second, first],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                try Expect.equal(journal.count, 2, "journal count")
                try Expect.equal(
                    journal.entries.map(\.id.value),
                    [2, 1],
                    "source order retained"
                )
                try Expect.equal(
                    journal.entry(try Entry.ID(1))?.id,
                    first.id,
                    "entry lookup"
                )
                try Expect.throwsError("duplicate entry IDs") {
                    _ = try Journal(.init(
                        entries: [first, first],
                        chart: fixture.chart,
                        entities: fixture.entities
                    ))
                }
            }

            Step("journal revalidates entries against its own definitions") {
                let fixture = try V2JournalFixture()
                let entry = try fixture.entry()
                let balanceRoot = try Account(.init(code: "B", postable: false))
                let incomeRoot = try Account(.init(code: "W", postable: false))
                let alternateChart = try Chart(.init(
                    accounts: [balanceRoot, incomeRoot],
                    roots: [balanceRoot.reference, incomeRoot.reference],
                    parents: [:],
                    behavior: .init(carryforward: .identity)
                ))
                try Expect.throwsError("different chart missing posting accounts") {
                    _ = try Journal(.init(
                        entries: [entry],
                        chart: alternateChart,
                        entities: fixture.entities
                    ))
                }
                let emptyEntities = try Entities([])
                try Expect.throwsError("different registry missing entity") {
                    _ = try Journal(.init(
                        entries: [entry],
                        chart: fixture.chart,
                        entities: emptyEntities
                    ))
                }
            }
        }
    }
}
