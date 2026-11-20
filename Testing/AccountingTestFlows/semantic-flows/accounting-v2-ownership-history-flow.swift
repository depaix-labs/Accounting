import Accounting
import AccountingV2
import AccountingV2Fixtures
import Foundation
import TestFlows

private func ownershipDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let result = formatter.date(from: value) else {
        throw V2ClosingFixture.SampleError.invalidDate(value)
    }
    return result
}

extension AccountingTestFlowsSuite {
    static var accountingV2OwnershipHistoryFlow: TestFlow {
        TestFlow("accounting-v2-ownership-history", tags: ["accounting", "v2", "ownership"]) {
            Step("explicit shares and V1 effective-date parity") {
                let start = try ownershipDate("2025-01-01")
                let before = try ownershipDate("2025-06-30")
                let changeDate = try ownershipDate("2025-07-01")
                let fixture = try V2ClosingFixture()

                let sixty = try Ownership.Share(percent: 60)
                let forty = try Ownership.Share(fraction: Decimal(4) / 10)
                try Expect.equal(sixty.fraction, Decimal(6) / 10, "explicit percentage conversion")
                try Expect.equal(forty.fraction, Decimal(4) / 10, "canonical fraction")

                let history = try Ownership.History(
                    owner: fixture.owner,
                    initial: Ownership.State(effectiveFrom: start, share: sixty),
                    changes: [
                        Ownership.Change(state: Ownership.State(
                            effectiveFrom: changeDate, share: forty,
                            details: "Revised agreement"
                        ))
                    ]
                )

                let legacy = OwnerEquity(
                    initial: OwnershipState(date: start, percentage: 60, details: nil),
                    changes: [OwnershipChange(state: OwnershipState(
                        date: changeDate, percentage: 40,
                        details: "Revised agreement"
                    ))]
                )

                try Expect.equal(history.state(at: before)?.share.fraction, legacy.percentage(on: before) / 100, "before-change V1 parity")
                try Expect.equal(history.state(at: changeDate)?.share.fraction, legacy.percentage(on: changeDate) / 100, "inclusive change-date V1 parity")
                try Expect.equal(history.state(at: changeDate)?.details, legacy.state(on: changeDate).details, "details parity")
                try Expect.equal(history.state(at: start.addingTimeInterval(-1)) == nil, true, "no invented pre-initial state")
                try Expect.equal(history.change(at: before) == nil, true, "no earlier change")
                try Expect.equal(history.changes.count, 1, "original event retained")
            }

            Step("independent owner timelines and divide relationships") {
                let fixture = try V2ClosingFixture()
                let start = try ownershipDate("2025-01-01")
                let before = try ownershipDate("2025-06-30")
                let changeDate = try ownershipDate("2025-07-01")
                let after = try ownershipDate("2025-10-01")
                let later = try ownershipDate("2026-01-01")

                let division = Ownership.Division(
                    recipient: fixture.secondOwner,
                    share: try Ownership.Share(percent: 10)
                )
                let first = try Ownership.History(
                    owner: fixture.owner,
                    initial: Ownership.State(
                        effectiveFrom: start,
                        share: Ownership.Share(percent: 60)
                    ),
                    changes: [
                        Ownership.Change(
                            state: Ownership.State(
                                effectiveFrom: changeDate,
                                share: Ownership.Share(percent: 40)
                            ),
                            divisions: [division]
                        ),
                        Ownership.Change(state: Ownership.State(
                            effectiveFrom: later,
                            share: Ownership.Share(percent: 40)
                        ))
                    ]
                )
                let second = try Ownership.History(
                    owner: fixture.secondOwner,
                    initial: Ownership.State(
                        effectiveFrom: start,
                        share: Ownership.Share(percent: 40)
                    ),
                    changes: [Ownership.Change(state: Ownership.State(
                        effectiveFrom: changeDate,
                        share: Ownership.Share(percent: 60)
                    ))]
                )
                let portfolio = try Ownership.Portfolio(
                    entities: fixture.entities,
                    histories: [first, second]
                )

                let prior = portfolio.states(at: before)
                let subsequent = portfolio.states(at: after)
                try Expect.equal(prior[fixture.owner]?.share.fraction, Decimal(6) / 10, "first owner before change")
                try Expect.equal(prior[fixture.secondOwner]?.share.fraction, Decimal(4) / 10, "second owner before change")
                try Expect.equal(subsequent[fixture.owner]?.share.fraction, Decimal(4) / 10, "first owner after change")
                try Expect.equal(subsequent[fixture.secondOwner]?.share.fraction, Decimal(6) / 10, "second owner after change")
                try Expect.equal(first.divisions(at: before).count, 0, "division not effective early")
                try Expect.equal(first.divisions(at: after).first?.recipient, fixture.secondOwner, "recipient retained")
                try Expect.equal(first.divisions(at: after).first?.share.fraction, Decimal(1) / 10, "division fraction")
                try Expect.equal(first.divisions(at: later).count, 0, "later change clears older division")
                try Expect.equal(portfolio.history(for: fixture.owner)?.changes.count, 2, "history retained")
                try Expect.equal(portfolio.states(at: start.addingTimeInterval(-1)).count, 0, "no premature ownership")
            }

            Step("reject ambiguous and invalid ownership facts") {
                let fixture = try V2ClosingFixture()
                let start = try ownershipDate("2025-01-01")
                let later = try ownershipDate("2025-07-01")
                let original = try Ownership.State(
                    effectiveFrom: start,
                    share: Ownership.Share(percent: 60)
                )
                let revision = try Ownership.State(
                    effectiveFrom: later,
                    share: Ownership.Share(percent: 40)
                )

                try Expect.throwsError("negative share") {
                    _ = try Ownership.Share(fraction: -1)
                }
                try Expect.throwsError("fraction above one") {
                    _ = try Ownership.Share(fraction: 2)
                }
                try Expect.throwsError("percent above 100") {
                    _ = try Ownership.Share(percent: 101)
                }
                try Expect.throwsError("change cannot precede initial") {
                    _ = try Ownership.History(
                        owner: fixture.owner,
                        initial: original,
                        changes: [Ownership.Change(state: original)]
                    )
                }
                try Expect.throwsError("duplicate effective dates") {
                    _ = try Ownership.History(
                        owner: fixture.owner,
                        initial: original,
                        changes: [
                            Ownership.Change(state: revision),
                            Ownership.Change(state: revision)
                        ]
                    )
                }

                let ten = try Ownership.Share(percent: 10)
                let sixty = try Ownership.Share(percent: 60)
                try Expect.throwsError("duplicate divide recipient") {
                    _ = try Ownership.Change(state: revision, divisions: [
                        Ownership.Division(recipient: fixture.secondOwner, share: ten),
                        Ownership.Division(recipient: fixture.secondOwner, share: ten)
                    ])
                }
                try Expect.throwsError("divide sum greater than whole") {
                    _ = try Ownership.Change(state: revision, divisions: [
                        Ownership.Division(recipient: fixture.owner, share: sixty),
                        Ownership.Division(recipient: fixture.secondOwner, share: sixty)
                    ])
                }

                let unknown = try Entity.Reference(
                    class: "person", family: "owner",
                    alias: Entity.Alias(name: "unknown")
                )
                let ordinary = try Ownership.History(owner: fixture.owner, initial: original)
                try Expect.throwsError("unknown owner") {
                    _ = try Ownership.Portfolio(
                        entities: fixture.entities,
                        histories: [Ownership.History(owner: unknown, initial: original)]
                    )
                }
                try Expect.throwsError("duplicate owner history") {
                    _ = try Ownership.Portfolio(
                        entities: fixture.entities,
                        histories: [ordinary, ordinary]
                    )
                }
                try Expect.throwsError("unresolved division recipient") {
                    let history = try Ownership.History(
                        owner: fixture.owner,
                        initial: original,
                        changes: [Ownership.Change(state: revision, divisions: [
                            Ownership.Division(recipient: unknown, share: ten)
                        ])]
                    )
                    _ = try Ownership.Portfolio(
                        entities: fixture.entities,
                        histories: [history]
                    )
                }
                try Expect.throwsError("self-division") {
                    let history = try Ownership.History(
                        owner: fixture.owner,
                        initial: original,
                        changes: [Ownership.Change(state: revision, divisions: [
                            Ownership.Division(recipient: fixture.owner, share: ten)
                        ])]
                    )
                    _ = try Ownership.Portfolio(
                        entities: fixture.entities,
                        histories: [history]
                    )
                }
            }
        }
    }
}
