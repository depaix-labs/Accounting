import Foundation
import AccountingV2
import TestFlows

extension AccountingTestFlowsSuite {
    static var accountingV2LedgerFlow: TestFlow {
        TestFlow("accounting-v2-ledger", tags: ["accounting", "v2", "ledger"]) {
            Step("posting construction validates source coordinates") {
                let fixture = try V2JournalFixture()
                let entry = try fixture.entry()
                let journal = try Journal(.init(
                    entries: [entry],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))

                try Expect.throwsError("invalid entry offset") {
                    _ = try Posting(.init(
                        journal: journal, entryIndex: 1, lineIndex: 0
                    ))
                }
                try Expect.throwsError("negative entry offset") {
                    _ = try Posting(.init(
                        journal: journal, entryIndex: -1, lineIndex: 0
                    ))
                }
                try Expect.throwsError("invalid line offset") {
                    _ = try Posting(.init(
                        journal: journal, entryIndex: 0, lineIndex: 2
                    ))
                }
                try Expect.throwsError("negative line offset") {
                    _ = try Posting(.init(
                        journal: journal, entryIndex: 0, lineIndex: -1
                    ))
                }

                let posting = try Posting(.init(
                    journal: journal, entryIndex: 0, lineIndex: 0
                ))
                try Expect.equal(posting.source.entryID, entry.id, "entry identity")
                try Expect.equal(posting.source.entryIndex, 0, "entry coordinate")
                try Expect.equal(posting.source.lineIndex, 0, "line coordinate")
                try Expect.equal(posting.account, fixture.bank, "source account")
                try Expect.equal(posting.entity, fixture.owner, "source entity")
                try Expect.equal(posting.direction, .debit, "source direction")
                try Expect.equal(posting.amount, 100, "original magnitude")
                try Expect.equal(posting.signedAmount, 100, "debit contribution")
                try Expect.equal(posting.date, entry.date, "source date")
            }

            Step("ledger retains authoritative journal and source ordering") {
                let fixture = try V2JournalFixture()
                let second = try fixture.entry(id: 2, amount: 250)
                let first = try fixture.entry(id: 1, amount: 100)
                let journal = try Journal(.init(
                    entries: [second, first],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))

                try Expect.equal(ledger.count, 4, "posting count")
                try Expect.equal(
                    ledger.journal.entries.map(\.id.value),
                    [2, 1],
                    "authoritative journal retained"
                )
                try Expect.equal(
                    ledger.postings.map(\.source.entryID.value),
                    [2, 2, 1, 1],
                    "entry order preserved"
                )
                try Expect.equal(
                    ledger.postings.map(\.source.lineIndex),
                    [0, 1, 0, 1],
                    "line order preserved"
                )
                try Expect.equal(
                    ledger.postings.map(\.signedAmount),
                    [250, -250, 100, -100],
                    "signed source contributions"
                )
                try Expect.equal(
                    ledger.postings[0].line.amount,
                    second.lines[0].amount,
                    "original line preserved"
                )
                try Expect.equal(
                    ledger.entry(first.id)?.id,
                    first.id,
                    "original entry accessible"
                )
            }

            Step("lookup indexes retain direct posting provenance") {
                let fixture = try V2JournalFixture()
                let first = try fixture.entry(id: 1, amount: 100)
                let second = try fixture.entry(id: 2, amount: 200)
                let journal = try Journal(.init(
                    entries: [first, second],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))

                try Expect.equal(
                    ledger.postings(for: first.id).map(\.source.lineIndex),
                    [0, 1],
                    "entry index"
                )
                try Expect.equal(
                    ledger.postings(for: fixture.bank).map(\.signedAmount),
                    [100, 200],
                    "direct account postings"
                )
                try Expect.equal(
                    ledger.postings(for: fixture.revenue).map(\.signedAmount),
                    [-100, -200],
                    "opposite-side postings"
                )
                try Expect.equal(
                    ledger.postings(for: fixture.owner).count,
                    4,
                    "entity postings"
                )

                let heading = try Account.Reference("B")
                try Expect.equal(
                    ledger.postings(for: heading).count,
                    0,
                    "headings are not populated with synthetic postings"
                )
                let missing = try Account.Reference("missing")
                try Expect.equal(
                    ledger.postings(for: missing).count,
                    0,
                    "unknown accounts have no direct postings"
                )
            }

            Step("empty journal produces an empty valid ledger") {
                let fixture = try V2JournalFixture()
                let journal = try Journal(.init(
                    entries: [],
                    chart: fixture.chart,
                    entities: fixture.entities
                ))
                let ledger = try Ledger(.init(journal: journal))

                try Expect.equal(ledger.count, 0, "no generated postings")
                try Expect.equal(ledger.journal.count, 0, "empty source retained")
                try Expect.equal(
                    ledger.postings(for: fixture.bank).count,
                    0,
                    "empty account lookup"
                )
            }
        }
    }
}
