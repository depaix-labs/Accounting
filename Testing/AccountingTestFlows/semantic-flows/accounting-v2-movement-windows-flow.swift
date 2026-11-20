import Foundation
import AccountingV2
import AccountingV2Fixtures
import TestFlows

private func windowFixtureDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    guard let date = formatter.date(from: value) else {
        throw V2ClosingFixture.SampleError.invalidDate(value)
    }
    return date
}

private func windowFixtureCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}

extension AccountingTestFlowsSuite {
    static var accountingV2MovementWindowsFlow: TestFlow {
        TestFlow("accounting-v2-movement-windows", tags: ["accounting", "v2", "movements"]) {
            Step("two calendar windows default to previous and current") {
                let selection = try MovementSelection(
                    anchor: windowFixtureDate("2026-10-15"),
                    unit: .month,
                    calendar: windowFixtureCalendar()
                )
                try Expect.equal(selection.windows.count, 2, "default comparison count")
                try Expect.equal(selection.windows.map(\.role), [.previous, .current], "roles")
                try Expect.equal(selection.previous?.start, windowFixtureDate("2026-09-01"), "September starts")
                try Expect.equal(selection.previous?.end, windowFixtureDate("2026-10-01"), "September ends")
                try Expect.equal(selection.current?.start, windowFixtureDate("2026-10-01"), "October starts")
                try Expect.equal(selection.current?.end, windowFixtureDate("2026-11-01"), "October ends")

                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let slices = MovementSlices(.init(ledger: ledger, selection: selection))
                try Expect.equal(slices.recorded_before.postings.count, 6, "earlier history once")
                try Expect.equal(slices.window(for: .previous)?.movements.postings.count, 2, "September postings")
                try Expect.equal(slices.window(for: .current)?.movements.postings.count, 2, "October postings")
                try Expect.equal(slices.window(for: .previous)?.movements.amount(for: fixture.bank)?.posted ?? -1, 80, "September bank")
                try Expect.equal(slices.window(for: .current)?.movements.amount(for: fixture.bank)?.posted ?? 1, -10, "October bank")
                try Expect.equal(slices.window(for: .previous)?.movements.amount(for: fixture.heading)?.total ?? -1, 0, "September balanced")
                try Expect.equal(slices.window(for: .current)?.movements.amount(for: fixture.heading)?.total ?? -1, 0, "October balanced")
                try Expect.equal(slices.window(for: .previous)?.movements.amount(for: fixture.bank, entity: fixture.secondOwner)?.posted ?? -1, 80, "entity attribution")
                try Expect.equal(ledger.postings.count, 12, "original ledger untouched")
            }

            Step("arbitrary counts keep empty windows and stable source identity") {
                let fixture = try V2ClosingFixture()
                let ledger = try fixture.sampleLedger()
                let selection = try MovementSelection(
                    anchor: windowFixtureDate("2026-10-15"),
                    unit: .month,
                    count: 4,
                    calendar: windowFixtureCalendar()
                )
                let slices = MovementSlices(.init(ledger: ledger, selection: selection))
                try Expect.equal(selection.windows.map(\.role), [.offset(-3), .offset(-2), .previous, .current], "four ordered roles")
                try Expect.equal(slices.windows.map { $0.movements.postings.count }, [0, 0, 2, 2], "July and August retained")
                try Expect.equal(slices.recorded_before.postings.count, 6, "recorded prefix")
                let september = slices.window(for: .previous)?.movements.postings ?? []
                try Expect.equal(september.map { $0.source.entryID.value }, [5, 5], "original entry identity retained")
                try Expect.equal(september.map { $0.source.lineIndex }, [0, 1], "original line indices retained")
            }

            Step("calendar day windows respect daylight saving time") {
                var calendar = windowFixtureCalendar()
                guard let timeZone = TimeZone(identifier: "Europe/Amsterdam") else {
                    throw V2ClosingFixture.SampleError.invalidDate("Europe/Amsterdam")
                }
                calendar.timeZone = timeZone
                let selection = try MovementSelection(
                    anchor: windowFixtureDate("2026-03-29"),
                    unit: .day,
                    calendar: calendar
                )
                guard let previous = selection.previous, let current = selection.current else {
                    throw V2ClosingFixture.SampleError.invalidDate("missing day window")
                }
                try Expect.equal(previous.end, current.start, "calendar boundaries touch")
                try Expect.equal(previous.end.timeIntervalSince(previous.start), 86400, "previous day is 24 hours")
                try Expect.equal(current.end.timeIntervalSince(current.start), 82800, "DST day is 23 hours")
            }

            Step("explicit selections reject overlapping and duplicated windows") {
                let first = try windowFixtureDate("2026-01-01")
                let middle = try windowFixtureDate("2026-02-01")
                let last = try windowFixtureDate("2026-03-01")
                let earlier = MovementSelection.Window(role: .previous, start: first, end: middle)
                let later = MovementSelection.Window(role: .current, start: middle, end: last)
                let explicit = try MovementSelection(.init(source: .explicit([earlier, later])))
                try Expect.equal(explicit.windows.count, 2, "explicit windows")
                try Expect.throwsError("overlap rejected") {
                    _ = try MovementSelection(.init(source: .explicit([
                        earlier,
                        .init(role: .current, start: first, end: last)
                    ])))
                }
                try Expect.throwsError("duplicate role rejected") {
                    _ = try MovementSelection(.init(source: .explicit([
                        earlier,
                        .init(role: .previous, start: middle, end: last)
                    ])))
                }
                try Expect.throwsError("zero count rejected") {
                    _ = try MovementSelection(
                        anchor: first,
                        unit: .month,
                        count: 0,
                        calendar: windowFixtureCalendar()
                    )
                }
            }
        }
    }
}
