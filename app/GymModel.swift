import Foundation

// MARK: - Config

struct GymConfig: Codable, Equatable {
    var start: String        // "2026-01-01"
    var end: String          // "2026-05-01"
    var totalFee: Double     // 10000
    var days: [Int]          // 1 = Sunday ... 7 = Saturday (Calendar convention)
    var minMinutes: Int      // 50
    var trackFrom: String    // "2026-01-01"
    var seedMissed: Int      // 0
    var skipDates: [String]  // ["2026-10-20"] travel, illness, gym closed
    var restored: [String]   // broken days you repaired with a weekend session

    /// Neutral starting point for a fresh install. Real values come from
    /// gym_config.json, written by the Install script or the Setup tab.
    static var fallback: GymConfig {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .month, value: 4, to: today) ?? today
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return GymConfig(
            start: f.string(from: today),
            end: f.string(from: end),
            totalFee: 10000,
            days: [2, 3, 4, 5, 6],      // Mon to Fri
            minMinutes: 45,
            trackFrom: f.string(from: today),
            seedMissed: 0,
            skipDates: [],
            restored: []
        )
    }

    // Older gym_config.json files will not have every key. Decode
    // tolerantly so a new field never wipes an existing setup.
    init(start: String, end: String, totalFee: Double, days: [Int],
         minMinutes: Int, trackFrom: String, seedMissed: Int,
         skipDates: [String], restored: [String]) {
        self.start = start; self.end = end; self.totalFee = totalFee
        self.days = days; self.minMinutes = minMinutes; self.trackFrom = trackFrom
        self.seedMissed = seedMissed; self.skipDates = skipDates; self.restored = restored
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fb = GymConfig.fallback
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? fb.start
        end = try c.decodeIfPresent(String.self, forKey: .end) ?? fb.end
        totalFee = try c.decodeIfPresent(Double.self, forKey: .totalFee) ?? fb.totalFee
        days = try c.decodeIfPresent([Int].self, forKey: .days) ?? fb.days
        minMinutes = try c.decodeIfPresent(Int.self, forKey: .minMinutes) ?? fb.minMinutes
        trackFrom = try c.decodeIfPresent(String.self, forKey: .trackFrom) ?? fb.trackFrom
        seedMissed = try c.decodeIfPresent(Int.self, forKey: .seedMissed) ?? 0
        skipDates = try c.decodeIfPresent([String].self, forKey: .skipDates) ?? []
        restored = try c.decodeIfPresent([String].self, forKey: .restored) ?? []
    }
}

// MARK: - Date helpers

enum GymDate {
    static let cal = Calendar.current

    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let stampFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func key(_ d: Date) -> String { fmt.string(from: d) }
    static func date(_ s: String) -> Date? { fmt.date(from: s) }
    static func today() -> Date { cal.startOfDay(for: Date()) }

    /// Every calendar day from a to b inclusive.
    static func range(_ a: Date, _ b: Date) -> [Date] {
        guard a <= b else { return [] }
        var out: [Date] = []
        var d = cal.startOfDay(for: a)
        let end = cal.startOfDay(for: b)
        while d <= end {
            out.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }
}

// MARK: - Log entries

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    var tag: String      // IN, OUT, MANUAL
    var stamp: Date

    var line: String { "\(tag),\(GymDate.stampFmt.string(from: stamp))" }

    static func parse(_ raw: String) -> LogEntry? {
        guard let comma = raw.firstIndex(of: ",") else { return nil }
        let tag = String(raw[raw.startIndex..<comma])
            .trimmingCharacters(in: .whitespaces).uppercased()
        let rest = String(raw[raw.index(after: comma)...])
            .trimmingCharacters(in: .whitespaces)
        guard let stamp = GymDate.stampFmt.date(from: rest) else { return nil }
        return LogEntry(tag: tag, stamp: stamp)
    }
}

/// One day in the commitment, after all the rules are applied.
struct DayStatus: Identifiable, Equatable {
    var id: String { key }
    var key: String
    var date: Date
    var scheduled: Bool
    var attended: Bool
    var manual: Bool
    var skipped: Bool
    var durationMinutes: Int?
    var isToday: Bool
    var isFuture: Bool
    var arrival: Date?

    /// Today is never missed. There is still time to go.
    var missed: Bool {
        scheduled && !attended && !skipped && !isToday && !isFuture
    }
}

// MARK: - Engine

/// Turns raw log lines plus config into everything the UI needs.
/// Mirrors the logic in GymWidget.js so the two never disagree.
struct GymEngine {

    let config: GymConfig
    let entries: [LogEntry]

    private var startDate: Date { GymDate.date(config.start) ?? GymDate.today() }
    private var endDate: Date { GymDate.date(config.end) ?? GymDate.today() }
    private var trackFromDate: Date { GymDate.date(config.trackFrom) ?? startDate }
    private var skipSet: Set<String> { Set(config.skipDates) }

    /// Rupees lost per missed session, fixed across the whole commitment.
    var rate: Double {
        let total = GymDate.range(startDate, endDate)
            .filter { config.days.contains(GymDate.cal.component(.weekday, from: $0)) }
            .count
        return total > 0 ? config.totalFee / Double(total) : 0
    }

    /// Days a qualifying session happened, with how long it ran.
    var attendance: [String: (manual: Bool, minutes: Int?, arrival: Date?)] {
        var out: [String: (manual: Bool, minutes: Int?, arrival: Date?)] = [:]
        var pendingIn: Date?

        for e in entries.sorted(by: { $0.stamp < $1.stamp }) {
            switch e.tag {
            case "IN":
                // Duplicate arrivals fire on GPS drift. Keep the earliest of the day.
                if let p = pendingIn, GymDate.key(p) == GymDate.key(e.stamp) { break }
                pendingIn = e.stamp

            case "OUT":
                guard let p = pendingIn else { break }
                let mins = Int(e.stamp.timeIntervalSince(p) / 60)
                if mins >= config.minMinutes {
                    out[GymDate.key(p)] = (false, mins, p)
                }
                pendingIn = nil

            case "MANUAL":
                let k = GymDate.key(e.stamp)
                if out[k] == nil { out[k] = (true, nil, nil) }

            default:
                break
            }
        }
        return out
    }

    /// Every day of the commitment from the tracking start, in order.
    /// Includes days still ahead so the punch strip shows the whole run.
    var timeline: [DayStatus] {
        let att = attendance
        let today = GymDate.today()
        return GymDate.range(trackFromDate, endDate).map { d in
            let k = GymDate.key(d)
            let a = att[k]
            return DayStatus(
                key: k,
                date: d,
                scheduled: config.days.contains(GymDate.cal.component(.weekday, from: d)),
                attended: a != nil,
                manual: a?.manual ?? false,
                skipped: skipSet.contains(k),
                durationMinutes: a?.minutes ?? nil,
                isToday: d == today,
                isFuture: d > today,
                arrival: a?.arrival ?? nil
            )
        }
    }

    /// Days that have already happened, newest last. Drives the Days list.
    var elapsed: [DayStatus] { timeline.filter { !$0.isFuture } }

    private var settled: [DayStatus] {
        timeline.filter { $0.date < GymDate.today() }
    }

    /// Repaired days are not misses. You did the session, just later.
    var missedCount: Int {
        settled.filter { $0.missed && !config.restored.contains($0.key) }.count + config.seedMissed
    }
    var wentCount: Int { elapsed.filter { $0.attended }.count }
    var burnt: Double { Double(missedCount) * rate }

    /// Cumulative rupees burnt, one point per day, for the chart.
    var burnCurve: [(date: Date, amount: Double)] {
        var running = Double(config.seedMissed) * rate
        var out: [(Date, Double)] = []
        for day in settled {
            if day.missed && !config.restored.contains(day.key) { running += rate }
            out.append((day.date, running))
        }
        return out.map { (date: $0.0, amount: $0.1) }
    }

    var todayIsScheduled: Bool {
        config.days.contains(GymDate.cal.component(.weekday, from: GymDate.today()))
            && !skipSet.contains(GymDate.key(GymDate.today()))
    }

    var todayDone: Bool { attendance[GymDate.key(GymDate.today())] != nil }

    var nextScheduled: Date? {
        var d = GymDate.cal.date(byAdding: .day, value: 1, to: GymDate.today())!
        for _ in 0..<14 {
            if d > endDate { return nil }
            let k = GymDate.key(d)
            if config.days.contains(GymDate.cal.component(.weekday, from: d)) && !skipSet.contains(k) {
                return d
            }
            d = GymDate.cal.date(byAdding: .day, value: 1, to: d)!
        }
        return nil
    }
}

// MARK: - Week helpers

extension GymDate {
    /// Calendar with weeks starting Monday, so a make-up weekend belongs
    /// to the week it repays.
    static var weekCal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    static func weekStart(_ d: Date) -> Date {
        let c = weekCal
        return c.date(from: c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? d
    }

    static func weekEnd(_ d: Date) -> Date {
        weekCal.date(byAdding: .day, value: 6, to: weekStart(d)) ?? d
    }

    static func weekdayName(_ n: Int, short: Bool = false) -> String {
        let f = DateFormatter()
        let arr = short ? f.shortWeekdaySymbols! : f.weekdaySymbols!
        return arr[(n - 1 + 7) % 7]
    }
}

// MARK: - Streak and stats

extension GymEngine {

    /// Sessions logged on days that were never scheduled. Each one is a
    /// repair token for that week.
    private var makeupsByWeek: [Date: Int] {
        var m: [Date: Int] = [:]
        for d in elapsed where !d.scheduled && d.attended {
            m[GymDate.weekStart(d.date), default: 0] += 1
        }
        return m
    }

    private var restoredSet: Set<String> { Set(config.restored) }

    /// Tokens already spent, per week.
    private var spentByWeek: [Date: Int] {
        var m: [Date: Int] = [:]
        for k in config.restored {
            guard let d = GymDate.date(k) else { continue }
            m[GymDate.weekStart(d), default: 0] += 1
        }
        return m
    }

    /// A break stays broken until you spend a weekend session on it.
    /// Nothing is forgiven automatically.
    private func held(_ d: DayStatus) -> Bool {
        d.attended || restoredSet.contains(d.key)
    }

    /// Days you could repair right now, newest first, with the number of
    /// unspent weekend sessions available in that week.
    var repairable: [(day: DayStatus, tokensLeft: Int)] {
        let makeups = makeupsByWeek
        let spent = spentByWeek
        var out: [(DayStatus, Int)] = []
        var budget: [Date: Int] = [:]
        for (w, n) in makeups { budget[w] = n - (spent[w] ?? 0) }

        for d in judged.reversed() where !held(d) {
            let w = GymDate.weekStart(d.date)
            if (budget[w] ?? 0) > 0 {
                out.append((d, budget[w] ?? 0))
                budget[w]! -= 1
            }
        }
        return out.map { (day: $0.0, tokensLeft: $0.1) }
    }

    var canRepair: Bool { !repairable.isEmpty }

    /// Scheduled days that have already been decided. Today only counts
    /// once it is logged, so an unfinished day never breaks anything.
    private var judged: [DayStatus] {
        elapsed.filter { $0.scheduled && (!$0.isToday || $0.attended) }
    }

    /// Unspent weekend sessions with nothing to repair. Banked for later
    /// in the same week only.
    var spareTokens: Int {
        let makeups = makeupsByWeek
        let spent = spentByWeek
        let repairs = repairable.count
        let total = makeups.values.reduce(0, +) - spent.values.reduce(0, +)
        return max(0, total - repairs)
    }

    var currentStreak: Int {
        var n = 0
        for d in judged.reversed() {
            if held(d) { n += 1 } else { break }
        }
        return n
    }

    var longestStreak: Int {
        var best = 0, run = 0
        for d in judged {
            if held(d) { run += 1; best = max(best, run) } else { run = 0 }
        }
        return max(best, currentStreak)
    }

    /// Sunday of the current week, the deadline for spending a repair.
    var repayDeadline: Date { GymDate.weekEnd(GymDate.today()) }

    // MARK: Credit side

    var justified: Double { Double(wentCount) * rate }

    var attendanceRate: Double {
        let total = judged.count
        return total > 0 ? Double(judged.filter { held($0) }.count) / Double(total) : 0
    }

    var perfectWeeks: Int {
        let today = GymDate.today()
        let groups = Dictionary(grouping: judged) { GymDate.weekStart($0.date) }
        return groups.filter { start, days in
            GymDate.weekEnd(start) < today && !days.isEmpty && days.allSatisfy { held($0) }
        }.count
    }

    var daysSinceLastMiss: Int? {
        guard let last = judged.last(where: { !held($0) }) else { return nil }
        return GymDate.cal.dateComponents([.day], from: last.date, to: GymDate.today()).day
    }

    /// Of the days you missed, how often did you show up the very next
    /// scheduled day. Measures whether one skip turns into three.
    var recoveryRate: Double? {
        var chances = 0, recovered = 0
        for (i, d) in judged.enumerated() where !held(d) {
            guard i + 1 < judged.count else { continue }
            chances += 1
            if held(judged[i + 1]) { recovered += 1 }
        }
        return chances > 0 ? Double(recovered) / Double(chances) : nil
    }

    // MARK: Burnt side

    var missRate: Double { 1 - attendanceRate }

    /// Misses left before the burn crosses a line you set.
    func missBudget(before limit: Double) -> Int {
        guard rate > 0 else { return 0 }
        return max(0, Int(limit / rate) - missedCount)
    }

    var remainingScheduled: Int {
        timeline.filter { $0.scheduled && $0.isFuture }.count
    }

    /// Where the burn lands by the end if nothing changes.
    /// Needs a few weeks of data before it means anything.
    var projectedBurn: Double? {
        guard judged.count >= 15 else { return nil }
        return burnt + Double(remainingScheduled) * missRate * rate
    }

    /// Miss counts per weekday, only where there is enough history.
    private var weekdayMisses: [(weekday: Int, missed: Int, total: Int)] {
        Dictionary(grouping: judged) { GymDate.cal.component(.weekday, from: $0.date) }
            .map { (weekday: $0.key, missed: $0.value.filter { !held($0) }.count, total: $0.value.count) }
            .filter { $0.total >= 3 }
    }

    var worstWeekday: (name: String, missed: Int, total: Int)? {
        guard let w = weekdayMisses.filter({ $0.missed > 0 })
            .max(by: { Double($0.missed)/Double($0.total) < Double($1.missed)/Double($1.total) })
        else { return nil }
        return (GymDate.weekdayName(w.weekday), w.missed, w.total)
    }

    var bestWeekday: (name: String, went: Int, total: Int)? {
        guard let w = weekdayMisses
            .max(by: { Double($0.missed)/Double($0.total) > Double($1.missed)/Double($1.total) })
        else { return nil }
        return (GymDate.weekdayName(w.weekday), w.total - w.missed, w.total)
    }
}

extension GymEngine {
    /// How far through the commitment window today sits. Drives the ring.
    var elapsedFraction: Double {
        let s = GymDate.date(config.start) ?? GymDate.today()
        let e = GymDate.date(config.end) ?? GymDate.today()
        let total = GymDate.cal.dateComponents([.day], from: s, to: e).day ?? 0
        let gone = GymDate.cal.dateComponents([.day], from: s, to: GymDate.today()).day ?? 0
        guard total > 0 else { return 0 }
        return max(0, min(1, Double(gone) / Double(total)))
    }
}
