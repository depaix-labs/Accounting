import Foundation

/// Source entry membership for each reporting period.
///
/// Offsets refer to one authoritative resolved-entry collection.
/// A source entry may belong to several overlapping reporting views,
/// but its identity and contents are not reconstructed or flattened.
public struct PeriodEntrySelection: Sendable {
    public let sourceEntries: [ResolvedEntry]
    public let windows: PeriodWindows

    public let historicalOffsets: [Int]
    public let windowOffsets: [Int]
    public let ytdOffsets: [Int]

    /// Nil means no comparable previous reporting period exists.
    public let previousOffsets: [Int]?
    public let previousHistoricalOffsets: [Int]?
    public let previousHistoricalWindow: PeriodWindow?

    /// Entries without an absolute date are retained in sourceEntries,
    /// but are not assigned to a reporting window.
    public let unresolvedDateOffsets: [Int]

    public init(
        sourceEntries: [ResolvedEntry],
        windows: PeriodWindows,
        calendar: Calendar
    ) {
        let previousHistoricalWindow: PeriodWindow? = windows.previous.map { previous in
            PeriodWindow(
                from: nil,
                to: previous.from.map { start in
                    let previousDay = calendar.date(
                        byAdding: .day,
                        value: -1,
                        to: start
                    )!
                    return calendar.dayEnd(previousDay)
                }
            )
        }

        var historical: [Int] = []
        var window: [Int] = []
        var ytd: [Int] = []
        var previous: [Int] = []
        var previousHistorical: [Int] = []
        var unresolved: [Int] = []

        for (offset, entry) in sourceEntries.enumerated() {
            guard let date = absDate(entry.date) else {
                unresolved.append(offset)
                continue
            }

            if let range = windows.historical, within(date, window: range) {
                historical.append(offset)
            }

            if within(date, window: windows.window) {
                window.append(offset)
            }

            if within(date, window: windows.ytd) {
                ytd.append(offset)
            }

            if let range = windows.previous, within(date, window: range) {
                previous.append(offset)
            }

            if let range = previousHistoricalWindow, within(date, window: range) {
                previousHistorical.append(offset)
            }
        }

        self.sourceEntries = sourceEntries
        self.windows = windows
        self.previousHistoricalWindow = previousHistoricalWindow
        self.historicalOffsets = historical
        self.windowOffsets = window
        self.ytdOffsets = ytd
        self.previousOffsets = windows.previous == nil ? nil : previous
        self.previousHistoricalOffsets = previousHistoricalWindow == nil
            ? nil : previousHistorical
        self.unresolvedDateOffsets = unresolved
    }

    /// Materialize an existing reporting view only when a downstream
    /// consumer requires entries rather than source offsets.
    public func entries(at offsets: [Int]) -> [ResolvedEntry] {
        offsets.map { sourceEntries[$0] }
    }
}
