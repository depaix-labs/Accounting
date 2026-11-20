import Accounting
import AccountingCompiler
import Foundation
import plate
import Primitives
import TestFlows

extension AccountingTestFlowsSuite {
    static var accountingInvarianceFlow: TestFlow {
        TestFlow(
            "accounting-invariance",
            tags: ["accounting", "invariance"]
        ) {
            Step("resolved entry rules preserve typed diagnostics") {
                let entries = try ECModelFixtures.resolveEntries(
                    ECModelFixtures.validResolutionEntrySource
                )
                try Expect.equal(entries.count, 2, "resolved fixture count")

                let rules = Invariance<ResolvedEntry>([
                    .entry.nonempty,
                    .entry.balanced,
                    .entry.posting_date_resolved
                ])

                for entry in entries {
                    try Expect.equal(
                        rules.violations(for: entry).count,
                        0,
                        "valid resolved entry passes all rules"
                    )
                }

                var empty = entries[0]
                empty.lines = []
                let empty_violations = rules.violations(for: empty)
                try Expect.equal(empty_violations.count, 1, "empty entry fails")
                try Expect.equal(
                    empty_violations[0].code,
                    .custom("accounting.entry.empty"),
                    "typed empty-entry reason"
                )
                try Expect.equal(
                    empty_violations[0].path,
                    [.field("lines")],
                    "empty-entry diagnostic path"
                )

                var unbalanced = entries[0]
                unbalanced.lines = Array(unbalanced.lines.prefix(1))
                let balance_violations = rules.violations(for: unbalanced)
                try Expect.equal(balance_violations.count, 1, "unbalanced entry fails")
                try Expect.equal(
                    balance_violations[0].code,
                    .custom("accounting.entry.unbalanced"),
                    "typed imbalance reason"
                )

                var unresolved = entries[0]
                unresolved.date = .infer(day: try DayOfMonth(15))
                let date_violations = rules.violations(for: unresolved)
                try Expect.equal(date_violations.count, 1, "inferred posting date fails")
                try Expect.equal(
                    date_violations[0].code,
                    .custom("accounting.entry.posting_date_unresolved"),
                    "typed posting date reason"
                )
                try Expect.equal(
                    date_violations[0].path,
                    [.field("date")],
                    "posting date path"
                )
            }

            Step("depreciation audit horizons never depend on the current date") {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                do {
                    _ = try DepreciationAuditHorizon.endOfMonth(using: [], calendar: calendar)
                    try Expect.true(false, "empty resolved ledger cannot infer an audit month")
                } catch let error as DepreciationAuditHorizonError {
                    try Expect.equal(error, .noAbsoluteEntryDates, "typed missing-horizon error")
                }

                let resolved = try ECModelFixtures.resolveEntries(
                    ECModelFixtures.validResolutionEntrySource
                )
                let horizon = try DepreciationAuditHorizon.endOfMonth(
                    using: resolved, calendar: calendar
                )
                let components = calendar.dateComponents([.year, .month, .day], from: horizon)
                try Expect.equal(components.year, 2026, "historical horizon year")
                try Expect.equal(components.month, 8, "historical horizon month")
                try Expect.equal(components.day, 31, "historical horizon final day")

                var unresolved = resolved[0]
                unresolved.date = .infer(day: try DayOfMonth(15))
                let fixedEnd = Date(timeIntervalSince1970: 0)
                do {
                    _ = try DepreciationAuditRunner.run(
                        entities: EntityStore([:]),
                        accounts: AccountStore(nodes: []),
                        resolvedEntries: [unresolved],
                        through: fixedEnd
                    )
                    try Expect.true(false, "audit rejects unresolved posting dates")
                } catch let error as DepreciationAuditHorizonError {
                    try Expect.equal(error, .unresolvedEntryDate, "typed unresolved-date error")
                }

                let emptyReport = try DepreciationAuditRunner.run(
                    entities: EntityStore([:]),
                    accounts: AccountStore(nodes: []),
                    resolvedEntries: [],
                    through: fixedEnd
                )
                try Expect.equal(emptyReport.horizonEnd, fixedEnd, "explicit horizon permits empty ledger")
            }

            Step("ownership reporting dates remain explicit for unbounded windows") {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!

                let historical = calendar.date(from: DateComponents(
                    year: 2022, month: 6, day: 15
                ))!
                let changeDate = calendar.date(from: DateComponents(
                    year: 2025, month: 1, day: 1
                ))!
                let later = calendar.date(from: DateComponents(
                    year: 2026, month: 6, day: 15
                ))!

                let ownership = OwnerEquity(
                    initial: OwnershipState(
                        date: historical, percentage: 25, details: nil
                    ),
                    changes: [
                        OwnershipChange(
                            state: OwnershipState(
                                date: changeDate, percentage: 75, details: nil
                            )
                        )
                    ]
                )

                let lifetime = PeriodSlicer.resolve(
                    shape: .init(kind: .lifetime),
                    anchor: historical,
                    calendar: calendar
                )
                try Expect.equal(lifetime.window.to, nil, "lifetime window is open-ended")
                try Expect.equal(
                    ownership.percentage(on: lifetime.window.to ?? historical),
                    Decimal(25),
                    "unbounded historical reporting retains historical ownership"
                )
                try Expect.equal(
                    ownership.percentage(on: lifetime.window.to ?? later),
                    Decimal(75),
                    "changing the explicit anchor changes the ownership snapshot"
                )

                let bounded = PeriodSlicer.resolve(
                    shape: .init(kind: .year),
                    anchor: historical,
                    calendar: calendar
                )
                try Expect.true(bounded.window.to != nil, "year window has an end date")
                try Expect.equal(
                    ownership.percentage(on: bounded.window.to ?? later),
                    Decimal(25),
                    "bounded window end takes precedence over a later anchor"
                )
                try Expect.true(
                    bounded.previous?.to != nil,
                    "previous calendar-year comparison has a fixed end date"
                )
            }

            Step("transaction amount and currency rules") {
                let amount = TransactionAmount(
                    currency: "EUR",
                    gross: 100,
                    fee: 2,
                    net: 98
                )
                let rules = Invariance<TransactionAmount>([
                    .transaction.amounts_consistent,
                    .currency.valid(supported: ["EUR"])
                ])
                try Expect.equal(rules.violations(for: amount).count, 0, "valid EUR amount")

                var inconsistent = amount
                inconsistent.net = 99
                let net_violations = rules.violations(for: inconsistent)
                try Expect.equal(net_violations.count, 1, "inconsistent net fails")
                try Expect.equal(
                    net_violations[0].code,
                    .custom("accounting.transaction.amount_inconsistent"),
                    "typed net discrepancy"
                )
                try Expect.equal(
                    net_violations[0].path,
                    [.field("net")],
                    "net discrepancy path"
                )

                inconsistent.currency = "USD"
                try Expect.equal(
                    rules.violations(for: inconsistent).count,
                    2,
                    "independent currency and amount violations accumulate"
                )

                var missing_net = amount
                missing_net.net = nil
                try Expect.equal(
                    rules.violations(for: missing_net).count,
                    0,
                    "missing optional net does not imply inconsistent net"
                )

                var nonfinite = amount
                nonfinite.gross = .nan
                try Expect.equal(
                    rules.violations(for: nonfinite)[0].code,
                    .nonfinite_number,
                    "nonfinite Decimal is rejected"
                )
            }

            Step("transaction identity and reference rules") {
                let amount = TransactionAmount(currency: "EUR", gross: 10)
                let first = Transaction(
                    id: 10,
                    date: .absolute(Date(timeIntervalSince1970: 0)),
                    source: .manual,
                    amount: amount,
                    status: .cleared
                )

                let identification = Invariance<Transaction>([
                    .transaction.identified
                ])
                try Expect.equal(identification.violations(for: first).count, 0, "identified transaction")
                var unidentified = first
                unidentified.id = nil
                try Expect.equal(
                    identification.violations(for: unidentified)[0].code,
                    .custom("accounting.transaction.missing_id"),
                    "missing identifier reason"
                )

                var duplicate = first
                duplicate.details = "same identifier"
                let uniqueness = Invariance<[Transaction]>([
                    .transaction.unique_ids
                ])
                try Expect.equal(
                    uniqueness.violations(for: [first, duplicate]).count,
                    1,
                    "duplicate transaction IDs rejected"
                )
                try Expect.equal(
                    uniqueness.violations(for: [unidentified, unidentified]).count,
                    0,
                    "ID uniqueness applies only to identified records; store rejects missing IDs separately"
                )

                let store = try TransactionStore([first])
                let references = Invariance<[TransactionKey]>([
                    .references.resolved(in: store)
                ])
                try Expect.equal(
                    references.violations(for: [TransactionKey(10)]).count,
                    0,
                    "known reference resolves"
                )
                let missing = references.violations(for: [TransactionKey(11)])
                try Expect.equal(missing.count, 1, "unknown reference rejected")
                try Expect.equal(
                    missing[0].code,
                    .custom("accounting.transaction.reference_missing"),
                    "typed missing reference reason"
                )
                try Expect.equal(missing[0].path, [.index(0)], "reference array index")
            }

            Step("account and entity reference rules") {
                let resolved = try ECModelFixtures.resolveEntries(
                    ECModelFixtures.validResolutionEntrySource
                )
                let line = resolved[0].lines[0]
                let known_account = line.account
                let known_entity = line.entity

                let passing = Invariance<ResolvedLine>([
                    .account.exists(where: { $0 == known_account }),
                    .entity.exists(where: { $0 == known_entity })
                ])
                try Expect.equal(
                    passing.violations(for: line).count,
                    0,
                    "known account and entity"
                )

                let missing = Invariance<ResolvedLine>([
                    .account.exists(where: { _ in false }),
                    .entity.exists(where: { _ in false })
                ]).violations(for: line)
                try Expect.equal(missing.count, 2, "both missing references reported")
                try Expect.equal(
                    missing[0].code,
                    .custom("accounting.account.reference_missing"),
                    "missing account reason"
                )
                try Expect.equal(
                    missing[1].code,
                    .custom("accounting.entity.reference_missing"),
                    "missing entity reason"
                )
                try Expect.equal(missing[0].path, [.field("account")], "account path")
                try Expect.equal(missing[1].path, [.field("entity")], "entity path")
            }

            Step("allocation totals require exact decimal equality") {
                let rules = Invariance<[Decimal]>([
                    .allocation.totals_equal(to: 100)
                ])
                try Expect.equal(
                    rules.violations(for: [60, 40]).count,
                    0,
                    "exact Decimal total"
                )
                let missing = rules.violations(for: [60, 39])
                try Expect.equal(missing.count, 1, "allocation mismatch")
                try Expect.equal(
                    missing[0].code,
                    .custom("accounting.allocation.total_mismatch"),
                    "typed mismatch reason"
                )
                try Expect.equal(
                    rules.violations(for: [Decimal.nan])[0].code,
                    .nonfinite_number,
                    "nonfinite allocation rejected"
                )
            }

            Step("ownership timeline validates every effective-date boundary") {
                let initial = Date(timeIntervalSince1970: 100)
                let revised = Date(timeIntervalSince1970: 200)
                let abolished = Date(timeIntervalSince1970: 300)

                func owner(
                    _ alias: String,
                    initialPercent: Decimal,
                    revisedPercent: Decimal,
                    finalPercent: Decimal
                ) throws -> (EntityKey, EntityDef) {
                    let key = try EntityKey(
                        class: "owner",
                        family: "partner",
                        alias: EntityAlias.parse(alias)
                    )
                    let equity = OwnerEquity(
                        initial: OwnershipState(date: initial, percentage: initialPercent, details: nil),
                        changes: [
                            OwnershipChange(state: OwnershipState(
                                date: revised, percentage: revisedPercent, details: nil
                            )),
                            OwnershipChange(state: OwnershipState(
                                date: abolished, percentage: finalPercent, details: nil
                            ))
                        ]
                    )
                    return (key, EntityDef(key: key, ownerEquity: equity))
                }

                let levi = try owner("levi", initialPercent: 50, revisedPercent: 47, finalPercent: 50)
                let casper = try owner("casper", initialPercent: 50, revisedPercent: 47, finalPercent: 50)
                let reallocation = try owner("reallocation", initialPercent: 0, revisedPercent: 6, finalPercent: 0)
                let valid = EntityStore(Dictionary(uniqueKeysWithValues: [levi, casper, reallocation]))
                try valid.validateOwnershipTimeline(timeZone: .current)
                try Expect.equal(
                    valid.ownershipSlices(asOf: abolished).reduce(Decimal.zero) { $0 + $1.percent },
                    Decimal(1),
                    "zero reallocation restores full direct ownership"
                )

                let excess = try owner("levi", initialPercent: 50, revisedPercent: 48, finalPercent: 50)
                let invalid = EntityStore(Dictionary(uniqueKeysWithValues: [excess, casper, reallocation]))
                try Expect.true(
                    ECModelFixtures.didThrow { try invalid.validateOwnershipTimeline(timeZone: .current) },
                    "101% at an intermediate effective date must fail"
                )

                let zero = try owner("zero", initialPercent: 0, revisedPercent: 0, finalPercent: 0)
                try Expect.true(
                    ECModelFixtures.didThrow {
                        try EntityStore(Dictionary(uniqueKeysWithValues: [zero])).validateOwnershipTimeline(timeZone: .current)
                    },
                    "an ownership history totaling zero must fail"
                )

                let tooLarge = try owner("large", initialPercent: 101, revisedPercent: 101, finalPercent: 101)
                try Expect.true(
                    ECModelFixtures.didThrow {
                        try EntityStore(Dictionary(uniqueKeysWithValues: [tooLarge])).validateOwnershipTimeline(timeZone: .current)
                    },
                    "individual percentages above 100 must fail"
                )

                let ninetyNine = try owner("ninety_nine", initialPercent: 99, revisedPercent: 99, finalPercent: 99)
                let one = try owner("one", initialPercent: 1, revisedPercent: 1, finalPercent: 1)
                let tinyShare = EntityStore(Dictionary(uniqueKeysWithValues: [ninetyNine, one]))
                try tinyShare.validateOwnershipTimeline(timeZone: .current)
                let oneID = tinyShare.idIndex[one.0]
                let oneSlice = tinyShare.ownershipSlices(asOf: revised).first { $0.entityId == oneID }
                try Expect.equal(oneSlice?.percent, Decimal(1) / 100, "1.00 means 1%, not 100%")

                try EntityStore([:]).validateOwnershipTimeline(timeZone: .current)
            }

            Step("ownership diagnostics respect configured timezone and DST") {
                guard let timeZone = TimeZone(identifier: "Europe/Amsterdam"),
                      let spring = parseLocalDateString("2026-03-29", timeZone: timeZone),
                      let summer = parseLocalDateString("2026-07-01", timeZone: timeZone),
                      let autumn = parseLocalDateString("2026-10-27", timeZone: timeZone)
                else {
                    try Expect.true(false, "Amsterdam timezone and local dates must resolve")
                    return
                }

                func expectInvalidTotal(on date: Date, displayedAs expectedDate: String) throws {
                    let key = try EntityKey(
                        class: "owner",
                        family: "partner",
                        alias: EntityAlias.parse("timezone_test")
                    )
                    let equity = OwnerEquity(
                        initial: OwnershipState(date: date, percentage: 95, details: nil),
                        changes: []
                    )
                    let store = EntityStore([
                        key: EntityDef(key: key, ownerEquity: equity)
                    ])

                    do {
                        try store.validateOwnershipTimeline(timeZone: timeZone)
                        try Expect.true(false, "95% ownership must be rejected")
                    } catch let error as OwnershipTimelineValidationError {
                        try Expect.equal(
                            error.errorDescription,
                            "Total ownership at \(expectedDate) is 95%; expected exactly 100.00%.",
                            "ownership error uses project-local calendar date"
                        )
                    }
                }

                try expectInvalidTotal(on: spring, displayedAs: "2026-03-29")
                try expectInvalidTotal(on: summer, displayedAs: "2026-07-01")
                try expectInvalidTotal(on: autumn, displayedAs: "2026-10-27")

                try Expect.equal(
                    OwnershipTimelineValidationError.invalidPercentage(
                        entity: "owner.test", date: autumn, actual: 101, timeZone: timeZone
                    ).errorDescription,
                    "Ownership percentage for owner.test at 2026-10-27 is 101; expected 0...100."
                )

                try Expect.equal(
                    OwnershipTimelineValidationError.duplicateChangeDate(
                        entity: "owner.test", date: autumn, timeZone: timeZone
                    ).errorDescription,
                    "Duplicate ownership change for owner.test at 2026-10-27."
                )

                try Expect.equal(
                    OwnershipTimelineValidationError.changeNotAfterInitial(
                        entity: "owner.test", date: autumn, initial: spring, timeZone: timeZone
                    ).errorDescription,
                    "Ownership change for owner.test at 2026-10-27 is not after initial date 2026-03-29."
                )
            }
        }
    }
}
