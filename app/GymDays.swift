import SwiftUI

// MARK: - Days

struct DaysView: View {
    @ObservedObject var store: GymStore
    @State private var mode = 0            // 0 calendar, 1 list
    @State private var month: Date = GymDate.cal.startOfDay(for: Date())
    @State private var picked: DayStatus?

    private var byKey: [String: DayStatus] {
        Dictionary(uniqueKeysWithValues: store.engine.timeline.map { ($0.key, $0) })
    }

    var body: some View {
        let e = store.engine
        Scaffold(onWhite: false) {
            ScreenHeader(
                title: "Days",
                caption: "\(e.wentCount) logged, \(e.missedCount) missed",
                trailing: AnyView(modeToggle)
            )
        } content: {
            Group {
                if mode == 0 {
                    CalendarPane(month: $month, byKey: byKey, tap: { picked = $0 })
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    ListPane(days: e.elapsed.reversed(), tap: { picked = $0 })
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.bottom, 150)
        }
        .sheet(item: $picked) { day in
            DayEditor(day: day, store: store)
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Ink.surface)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 3) {
            toggleButton(0, "square.grid.3x3.fill")
            toggleButton(1, "list.bullet")
        }
        .padding(4)
        .background(Capsule().fill(Ink.surface))
        .overlay(Capsule().stroke(Ink.hair, lineWidth: 1))
    }

    private func toggleButton(_ i: Int, _ icon: String) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { mode = i }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(mode == i ? Ink.black : Ink.sub)
                .frame(width: 38, height: 30)
                .background(Capsule().fill(mode == i ? Ink.paper : .clear))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calendar

struct CalendarPane: View {
    @Binding var month: Date
    let byKey: [String: DayStatus]
    let tap: (DayStatus) -> Void

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 26) {
            monthBar
            weekdayRow
            grid
            legend
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var monthBar: some View {
        HStack {
            navButton("chevron.left") { shift(-1) }
            Spacer()
            Text(monthTitle)
                .font(.figure(24, .bold))
                .foregroundStyle(Ink.text)
                .contentTransition(.opacity)
            Spacer()
            navButton("chevron.right") { shift(1) }
        }
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.easeInOut(duration: 0.25)) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Ink.text)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Ink.surface))
                .overlay(Circle().stroke(Ink.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var weekdayRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                Text(d)
                    .font(.tight(14, .semibold))
                    .foregroundStyle(Ink.faint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 52) }
            ForEach(daysInMonth, id: \.self) { date in
                let day = byKey[GymDate.key(date)]
                Cell(date: date, day: day)
                    .onTapGesture {
                        guard let day, !day.isFuture else { return }
                        Haptic.tap()
                        tap(day)
                    }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            item(Ink.text, filled: true, "went")
            item(Ink.loss, filled: false, "missed")
            item(Ink.warn, filled: false, "excused")
        }
        .padding(.top, 4)
    }

    private func item(_ c: Color, filled: Bool, _ label: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 4)
                .fill(filled ? c : .clear)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(c, lineWidth: 1.6))
                .frame(width: 13, height: 13)
            Text(label).font(.tight(14)).foregroundStyle(Ink.sub)
        }
    }

    // MARK: Cell

    private struct Cell: View {
        let date: Date
        let day: DayStatus?

        private var num: String { String(GymDate.cal.component(.day, from: date)) }

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(fill)
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(stroke, lineWidth: day?.isToday == true ? 2 : 1.4)
                VStack(spacing: 3) {
                    Text(num)
                        .font(.figure(17, .bold))
                        .foregroundStyle(numberTint)
                    if let m = day?.durationMinutes {
                        Text("\(m)m").font(.tight(11)).foregroundStyle(numberTint.opacity(0.65))
                    } else if day?.manual == true {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(numberTint.opacity(0.65))
                    }
                }
            }
            .frame(height: 52)
            .opacity(day == nil ? 0.25 : 1)
        }

        private var fill: Color {
            guard let day else { return .clear }
            if day.attended { return Ink.text }
            if day.skipped { return Ink.warn.opacity(0.16) }
            if day.missed { return Ink.loss.opacity(0.13) }
            return .clear
        }

        private var stroke: Color {
            guard let day else { return Ink.hair }
            if day.attended { return .clear }
            if day.skipped { return Ink.warn.opacity(0.7) }
            if day.missed { return Ink.loss.opacity(0.8) }
            if day.isToday { return Ink.text }
            if !day.scheduled { return Ink.hair.opacity(0.6) }
            return Ink.hair
        }

        private var numberTint: Color {
            guard let day else { return Ink.faint }
            if day.attended { return Ink.black }
            if day.missed { return Ink.loss }
            if day.skipped { return Ink.warn }
            if !day.scheduled { return Ink.faint }
            return Ink.sub
        }
    }

    // MARK: Maths

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: month)
    }

    private func shift(_ n: Int) {
        if let d = GymDate.cal.date(byAdding: .month, value: n, to: month) { month = d }
    }

    private var firstOfMonth: Date {
        GymDate.cal.date(from: GymDate.cal.dateComponents([.year, .month], from: month)) ?? month
    }

    private var daysInMonth: [Date] {
        guard let range = GymDate.cal.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap {
            GymDate.cal.date(byAdding: .day, value: $0 - 1, to: firstOfMonth)
        }
    }

    /// Monday-first offset for the first cell of the grid.
    private var leadingBlanks: Int {
        let wd = GymDate.cal.component(.weekday, from: firstOfMonth)  // 1 = Sunday
        return (wd + 5) % 7
    }
}

// MARK: - List

struct ListPane: View {
    let days: [DayStatus]
    let tap: (DayStatus) -> Void

    private var grouped: [(month: String, days: [DayStatus])] {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        var order: [String] = []
        var map: [String: [DayStatus]] = [:]
        for d in days {
            let k = f.string(from: d.date)
            if map[k] == nil { order.append(k); map[k] = [] }
            map[k]?.append(d)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped, id: \.month) { section in
                    Section {
                        ForEach(section.days) { d in
                            Row(day: d).onTapGesture { Haptic.tap(); tap(d) }
                            Hair().padding(.leading, 24)
                        }
                    } header: {
                        HStack {
                            Text(section.month.lowercased())
                                .font(.tight(15, .semibold))
                                .foregroundStyle(Ink.sub)
                            Spacer()
                            Text("\(section.days.filter { $0.attended }.count) went")
                                .font(.tight(15))
                                .foregroundStyle(Ink.faint)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Ink.black)
                    }
                }
        }
    }

    private struct Row: View {
        let day: DayStatus

        var body: some View {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(day.attended ? Ink.text : .clear)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(strokeTint, lineWidth: 1.6)
                    Text(String(GymDate.cal.component(.day, from: day.date)))
                        .font(.figure(16, .bold))
                        .foregroundStyle(day.attended ? Ink.black : strokeTint)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(weekday)
                        .font(.tight(18, .semibold))
                        .foregroundStyle(day.scheduled ? Ink.text : Ink.sub)
                    Text(detail)
                        .font(.tight(15))
                        .foregroundStyle(day.missed ? Ink.loss.opacity(0.9) : Ink.sub)
                }
                Spacer()
                if let a = day.arrival {
                    let f = DateFormatter(); let _ = (f.dateFormat = "HH:mm")
                    Text(f.string(from: a))
                        .font(.figure(17))
                        .foregroundStyle(Ink.faint)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }

        private var strokeTint: Color {
            if day.attended { return .clear }
            if day.missed { return Ink.loss }
            if day.skipped { return Ink.warn }
            if day.isToday { return Ink.text }
            return Ink.hair
        }

        private var weekday: String {
            let f = DateFormatter(); f.dateFormat = "EEEE"
            return f.string(from: day.date)
        }

        private var detail: String {
            if let m = day.durationMinutes { return "\(m) minutes" }
            if day.manual { return "marked by hand" }
            if day.skipped { return "excused" }
            if !day.scheduled { return "rest day" }
            if day.isToday { return "still time" }
            if day.missed { return "missed" }
            return ""
        }
    }
}

// MARK: - Day editor

struct DayEditor: View {
    let day: DayStatus
    @ObservedObject var store: GymStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(caption)
                    .font(.tight(15, .semibold))
                    .foregroundStyle(Ink.sub)
                Text(title)
                    .font(.figure(30, .heavy))
                    .foregroundStyle(Ink.text)
            }
            .padding(.top, 26)

            if let m = day.durationMinutes, let a = day.arrival {
                let f = DateFormatter(); let _ = (f.dateFormat = "HH:mm")
                Text("Arrived \(f.string(from: a)), stayed \(m) minutes.")
                    .font(.tight(16))
                    .foregroundStyle(Ink.sub)
                    .padding(.top, 8)
            }

            Spacer(minLength: 22)

            VStack(spacing: 10) {
                action(
                    day.attended ? "Clear this day" : "I went",
                    icon: day.attended ? "xmark" : "checkmark",
                    tint: day.attended ? Ink.sub : Ink.gain
                ) {
                    day.attended ? store.clearDay(day.date) : store.markAttended(day.date)
                    Haptic.success()
                    dismiss()
                }

                if day.scheduled {
                    action(
                        day.skipped ? "Charge this day" : "Excuse this day",
                        icon: day.skipped ? "indianrupeesign" : "pause",
                        tint: Ink.warn
                    ) {
                        store.toggleSkip(day.date)
                        Haptic.tap(.medium)
                        dismiss()
                    }
                }
            }

            Text(day.scheduled
                 ? "Excusing costs no money, but the streak still needs a weekend make-up that week."
                 : "This was not a scheduled day. Logging it here counts as a make-up session.")
                .font(.tight(14))
                .foregroundStyle(Ink.faint)
                .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func action(_ label: String, icon: String, tint: Color, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                Text(label).font(.tight(18, .bold))
                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 20)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(tint.opacity(0.45), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        let f = DateFormatter(); f.dateFormat = "d MMMM"
        return f.string(from: day.date)
    }

    private var caption: String {
        let f = DateFormatter(); f.dateFormat = "EEEE"
        return f.string(from: day.date).lowercased()
    }
}
