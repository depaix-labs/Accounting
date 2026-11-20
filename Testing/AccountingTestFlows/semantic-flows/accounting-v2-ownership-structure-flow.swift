import AccountingV2
import Foundation
import TestFlows

private func ownershipStructureDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let date = formatter.date(from: value) else {
        throw StructureFixtureError.invalidDate(value)
    }
    return date
}

private enum StructureFixtureError: Swift.Error {
    case invalidDate(String)
}

private struct StructureFixture {
    let structure: Ownership.Structure
    let ownerA: Entity.Reference
    let ownerB: Entity.Reference
    let pool: Entity.Reference
    let entrant: Entity.Reference
}

private func ownershipStructureFixture(
    entrantPercent: Decimal = 40,
    ownerADivisionPercent: Decimal = 50
) throws -> StructureFixture {
    func reference(_ name: String) throws -> Entity.Reference {
        try Entity.Reference(
            class: "person", family: "owner", alias: Entity.Alias(name: name)
        )
    }
    func state(_ date: String, _ percentage: Decimal) throws -> Ownership.State {
        try Ownership.State(
            effectiveFrom: ownershipStructureDate(date),
            share: Ownership.Share(percent: percentage)
        )
    }
    func change(_ date: String, _ percentage: Decimal) throws -> Ownership.Change {
        try Ownership.Change(state: state(date, percentage))
    }

    let ownerA = try reference("ownerA")
    let ownerB = try reference("ownerB")
    let pool = try reference("pool")
    let entrant = try reference("entrant")
    let entities = try Entities([
        Entity(.init(reference: ownerA)),
        Entity(.init(reference: ownerB)),
        Entity(.init(reference: pool)),
        Entity(.init(reference: entrant))
    ])

    let halves = [
        Ownership.Division(
            recipient: ownerA,
            share: try Ownership.Share(percent: ownerADivisionPercent)
        ),
        Ownership.Division(
            recipient: ownerB,
            share: try Ownership.Share(percent: 50)
        )
    ]
    let histories = [
        try Ownership.History(
            owner: ownerA,
            initial: state("2020-02-01", 50),
            changes: [
                change("2021-05-15", 40),
                change("2023-03-01", 30)
            ]
        ),
        try Ownership.History(
            owner: ownerB,
            initial: state("2020-02-01", 50),
            changes: [
                change("2021-05-15", 40),
                change("2023-03-01", 30)
            ]
        ),
        try Ownership.History(
            owner: pool,
            initial: state("2020-02-01", 0),
            changes: [
                Ownership.Change(
                    state: state("2021-05-15", 20), divisions: halves
                ),
                Ownership.Change(
                    state: state("2023-03-01", 40), divisions: halves
                ),
                change("2025-09-18", 0)
            ]
        ),
        try Ownership.History(
            owner: entrant,
            initial: state("2025-09-18", entrantPercent)
        )
    ]
    let portfolio = try Ownership.Portfolio(
        entities: entities,
        histories: histories
    )
    return try StructureFixture(
        structure: Ownership.Structure(
            portfolio: portfolio,
            collapsing: [pool]
        ),
        ownerA: ownerA,
        ownerB: ownerB,
        pool: pool,
        entrant: entrant
    )
}

extension AccountingTestFlowsSuite {
    static var accountingV2OwnershipStructureFlow: TestFlow {
        TestFlow("accounting-v2-ownership-structure", tags: ["accounting", "v2", "ownership"]) {
            Step("strict transition totals and four-entity temporal snapshots") {
                let fixture = try ownershipStructureFixture()
                let structure = fixture.structure
                try Expect.equal(structure.snapshots.count, 4, "all effective boundaries retained")
                try Expect.equal(
                    structure.snapshot(at: try ownershipStructureDate("2020-01-31")) == nil,
                    true,
                    "no invented ownership before inception"
                )
                let first = structure.snapshot(at: try ownershipStructureDate("2020-02-01"))
                let second = structure.snapshot(at: try ownershipStructureDate("2021-05-15"))
                let third = structure.snapshot(at: try ownershipStructureDate("2023-03-01"))
                let fourth = structure.snapshot(at: try ownershipStructureDate("2025-09-18"))
                try Expect.equal(first?.declared[fixture.ownerA], Decimal(1) / 2, "initial owner A")
                try Expect.equal(second?.declared[fixture.pool], Decimal(1) / 5, "20 percent pool")
                try Expect.equal(third?.declared[fixture.pool], Decimal(2) / 5, "40 percent pool")
                try Expect.equal(third?.declared[fixture.ownerA], Decimal(3) / 10, "declared owner")
                try Expect.equal(fourth?.declared[fixture.entrant], Decimal(2) / 5, "entrant joins")
                try Expect.equal(fourth?.declared[fixture.pool], 0, "pool abolished")
                for snapshot in structure.snapshots {
                    try Expect.equal(
                        snapshot.declared.values.reduce(Decimal.zero, +), 1,
                        "declared ownership conserves at each transition"
                    )
                    try Expect.equal(
                        snapshot.effective.values.reduce(Decimal.zero, +), 1,
                        "effective ownership conserves at each transition"
                    )
                }
            }

            Step("collapsing is a derived view, not a change to declared ownership") {
                let fixture = try ownershipStructureFixture()
                let atSecondRegime = try ownershipStructureDate("2023-06-01")
                let snapshot = fixture.structure.snapshot(at: atSecondRegime)
                try Expect.equal(snapshot?.declared[fixture.ownerA], Decimal(3) / 10, "original share retained")
                try Expect.equal(snapshot?.effective[fixture.ownerA], Decimal(1) / 2, "owner A receives 20 percent")
                try Expect.equal(snapshot?.effective[fixture.ownerB], Decimal(1) / 2, "owner B receives 20 percent")
                try Expect.equal(snapshot?.effective[fixture.pool] == nil, true, "collapsed pool has no terminal entitlement")
                try Expect.equal(snapshot?.routes[fixture.pool]?.count, 2, "division provenance retained")
                let uncollapsed = try Ownership.Structure(portfolio: fixture.structure.portfolio)
                try Expect.equal(
                    uncollapsed.snapshot(at: atSecondRegime)?.effective[fixture.pool],
                    Decimal(2) / 5,
                    "collapsing must be explicitly requested"
                )
                let beforeEntry = fixture.structure.snapshot(
                    at: try ownershipStructureDate("2025-09-17")
                )
                try Expect.equal(beforeEntry?.effective[fixture.ownerA], Decimal(1) / 2, "old regime until boundary")
                let afterEntry = fixture.structure.snapshot(
                    at: try ownershipStructureDate("2025-09-18")
                )
                try Expect.equal(afterEntry?.effective[fixture.ownerA], Decimal(3) / 10, "new owner A entitlement")
                try Expect.equal(afterEntry?.effective[fixture.ownerB], Decimal(3) / 10, "new owner B entitlement")
                try Expect.equal(afterEntry?.effective[fixture.entrant], Decimal(2) / 5, "new entrant entitlement")
            }

            Step("invalid ownership totals and incomplete collapses are rejected") {
                try Expect.throwsError("35 percent entrant leaves 5 percent missing") {
                    _ = try ownershipStructureFixture(entrantPercent: 35)
                }
                try Expect.throwsError("divisions must distribute all of a positive pool") {
                    _ = try ownershipStructureFixture(ownerADivisionPercent: 40)
                }
                let fixture = try ownershipStructureFixture()
                let absent = try Entity.Reference(
                    class: "person", family: "owner",
                    alias: Entity.Alias(name: "absent")
                )
                try Expect.throwsError("unknown collapse is invalid") {
                    _ = try Ownership.Structure(
                        portfolio: fixture.structure.portfolio,
                        collapsing: [absent]
                    )
                }
            }

            Step("monetary collapse conserves signed recorded capital") {
                let fixture = try ownershipStructureFixture()
                let date = try ownershipStructureDate("2023-06-01")
                let recorded: [Entity.Reference: Decimal] = [
                    fixture.ownerA: 11,
                    fixture.ownerB: -7,
                    fixture.pool: 101
                ]
                let result = try fixture.structure.distribute(recorded, at: date)
                try Expect.equal(result.recorded[fixture.pool], 101, "source capital retained")
                try Expect.equal(result.effective[fixture.ownerA], Decimal(123) / 2, "A receives half pool")
                try Expect.equal(result.effective[fixture.ownerB], Decimal(87) / 2, "B receives half pool")
                try Expect.equal(result.effective[fixture.pool] == nil, true, "pool has no effective balance")
                try Expect.equal(result.recordedTotal, 105, "signed recorded total")
                try Expect.equal(result.effectiveTotal, 105, "signed effective total")
                try Expect.equal(result.adjustments[fixture.ownerA], Decimal(101) / 2, "A attribution adjustment")
                try Expect.equal(result.adjustments[fixture.ownerB], Decimal(101) / 2, "B attribution adjustment")
                try Expect.equal(result.adjustments[fixture.pool], -101, "pool attribution adjustment")
                try Expect.equal(result.adjustmentTotal, 0, "no capital created or lost")

                let uncollapsed = try Ownership.Structure(portfolio: fixture.structure.portfolio)
                let original = try uncollapsed.distribute(recorded, at: date)
                try Expect.equal(original.effective[fixture.pool], 101, "collapse cannot be inferred")
                try Expect.equal(original.adjustmentTotal, 0, "no implicit reallocation")
            }

            Step("expired routes and inactive owners cannot absorb recorded balances") {
                let fixture = try ownershipStructureFixture()
                let inception = try ownershipStructureDate("2020-02-01")
                let ended = try ownershipStructureDate("2025-09-18")
                let before = try fixture.structure.distribute([fixture.pool: 0], at: inception)
                try Expect.equal(before.effectiveTotal, 0, "zero pool needs no route")
                try Expect.throwsError("positive pool capital without an initial route") {
                    _ = try fixture.structure.distribute([fixture.pool: 10], at: inception)
                }
                try Expect.throwsError("abolished pool capital requires an explicit route") {
                    _ = try fixture.structure.distribute([fixture.pool: 10], at: ended)
                }
                try Expect.throwsError("new owner is inactive before initial date") {
                    _ = try fixture.structure.distribute(
                        [fixture.entrant: 5], at: try ownershipStructureDate("2023-06-01")
                    )
                }
                try Expect.throwsError("no ownership snapshot before inception") {
                    _ = try fixture.structure.distribute(
                        [fixture.ownerA: 5], at: try ownershipStructureDate("2020-01-31")
                    )
                }
            }
        }
    }
}
