import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Root

struct RootView: View {
    @StateObject private var store = GymStore()
    @State private var tab = 0
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if store.isLinked && store.needsSetup {
                OnboardingView(store: store)
            } else if store.isLinked {
                ZStack(alignment: .bottom) {
                    (tab == 3 ? Ink.paper : Ink.black).ignoresSafeArea()

                    ZStack {
                        switch tab {
                        case 0: BurntView(store: store).transition(fade)
                        case 1: DaysView(store: store).transition(fade)
                        case 2: SetupView(store: store).transition(fade)
                        default: CreditView(store: store).transition(fade)
                        }
                    }

                    FloatingBar(tab: $tab, onWhite: tab == 3).padding(.bottom, 6)
                }
                // Status bar has to flip on the white screen or it vanishes.
                .preferredColorScheme(tab == 3 ? .light : .dark)
                // Coming back to the app always lands on what you owe.
                .onChange(of: phase) { _, new in
                    if new == .active { withAnimation { tab = 0 } }
                }
            } else {
                LinkFolderView(store: store).preferredColorScheme(.dark)
            }
        }
    }

    private var fade: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.985))
    }
}

// MARK: - First run

struct LinkFolderView: View {
    @ObservedObject var store: GymStore
    @State private var picking = false

    var body: some View {
        ZStack {
            Ink.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 26) {
                Spacer()
                Text("Point this at your Scriptable folder")
                    .font(.figure(38, .heavy))
                    .foregroundStyle(Ink.text)

                Text("Your widgets already write gym_log.txt into iCloud Drive. Pick that same folder and the app reads the exact file, so the two can never disagree.")
                    .font(.tight(17))
                    .foregroundStyle(Ink.sub)
                    .frame(maxWidth: 340, alignment: .leading)

                Button {
                    Haptic.tap()
                    picking = true
                } label: {
                    Text("Choose folder")
                        .font(.tight(19, .bold))
                        .foregroundStyle(Ink.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Capsule().fill(Ink.paper))
                }

                if let err = store.lastError {
                    Text(err).font(.tight(15)).foregroundStyle(Ink.loss)
                }
                Spacer()
            }
            .padding(.horizontal, 26)
        }
        .fileImporter(
            isPresented: $picking,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { store.linkFolder(url) }
            case .failure(let error):
                store.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - Burnt

struct BurntView: View {
    @ObservedObject var store: GymStore
    @State private var arc: Double = 0
    @State private var amount: Double = 0

    var body: some View {
        let e = store.engine
        Scaffold(onWhite: false, refresh: { store.reload() }) {
            header(e)
        } content: {
            VStack(spacing: 0) {
                if e.canRepair {
                    RepairCard(store: store)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                }

                if e.todayIsScheduled && !e.todayDone {
                    nudge(e)
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                }

                hero(e).padding(.top, 22)
                bracket(e).padding(.top, 2)

                VStack(spacing: 0) {
                    SectionLabel(text: "Pressure").padding(.bottom, 4)
                    pressure(e)
                }
                .padding(.horizontal, 24)
                .padding(.top, 42)

                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionLabel(text: "The whole run")
                        Text("\(e.wentCount) of \(e.timeline.filter { $0.scheduled }.count)")
                            .font(.figure(17))
                            .foregroundStyle(Ink.sub)
                    }
                    PunchStrip(days: e.timeline.filter { $0.scheduled }, onWhite: false)
                }
                .padding(.horizontal, 24)
                .padding(.top, 42)

                if e.burnCurve.count > 2 {
                    curve(e).padding(.horizontal, 24).padding(.top, 42)
                }
            }
            .padding(.bottom, 150)
        }
        .onAppear {
            arc = 0; amount = 0
            withAnimation(.easeOut(duration: 1.1)) { arc = e.elapsedFraction }
            withAnimation(.easeOut(duration: 0.9)) { amount = e.burnt }
        }
    }

    private func header(_ e: GymEngine) -> some View {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"
        let chip: Chip = {
            if e.todayDone { return Chip(text: "logged", tint: Ink.gain) }
            if e.todayIsScheduled { return Chip(text: "gym day", tint: Ink.loss) }
            return Chip(text: "rest day", tint: Ink.faint)
        }()
        return ScreenHeader(
            title: "Burnt",
            caption: f.string(from: Date()).lowercased(),
            trailing: AnyView(chip)
        )
    }

    private func nudge(_ e: GymEngine) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Ink.loss)
            VStack(alignment: .leading, spacing: 3) {
                Text("You owe today")
                    .font(.tight(19, .bold))
                    .foregroundStyle(Ink.text)
                Text("\(e.rate.rupees) goes up in smoke at midnight.")
                    .font(.tight(16))
                    .foregroundStyle(Ink.sub)
            }
            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Ink.loss.opacity(0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Ink.loss.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private func hero(_ e: GymEngine) -> some View {
        Gauge(progress: arc, tint: Ink.loss, track: Color(white: 0.13)) {
            VStack(spacing: 4) {
                CountUp(value: amount, font: .figure(60, .heavy),
                        color: e.burnt > 0 ? Ink.loss : Ink.text) { $0.rupees }
                    .padding(.horizontal, 34)
                Text(e.burnt > 0 ? "gone" : "still intact")
                    .font(.tight(18))
                    .foregroundStyle(Ink.sub)
                Text("\(Int(e.elapsedFraction * 100))% through the membership")
                    .font(.tight(13))
                    .foregroundStyle(Ink.faint)
                    .padding(.top, 6)
            }
        }
    }

    private func bracket(_ e: GymEngine) -> some View {
        VStack(spacing: 0) {
            Bracket()
                .stroke(Ink.hair, lineWidth: 1)
                .frame(height: 28)
                .padding(.horizontal, 48)
            HStack(spacing: 0) {
                Pill(value: "\(e.wentCount)", label: "went",
                     tint: Ink.text, stroke: Color(white: 0.38), labelTint: Ink.sub, delay: 0.05)
                Pill(value: "\(e.missedCount)", label: "missed",
                     tint: Ink.loss, stroke: Ink.loss.opacity(0.6), labelTint: Ink.loss.opacity(0.9), delay: 0.12)
                Pill(value: "\(Int((e.missRate * 100).rounded()))%", label: "miss rate",
                     tint: Ink.warn, stroke: Ink.warn.opacity(0.55), labelTint: Ink.warn.opacity(0.9), delay: 0.19)
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func pressure(_ e: GymEngine) -> some View {
        let budget = e.missBudget(before: 1000)
        VStack(spacing: 0) {
            LedgerRow("Misses left before ₹1,000", "\(budget)",
                      tint: budget <= 2 ? Ink.loss : Ink.text)
            Hair()
            if let p = e.projectedBurn {
                LedgerRow("Lands at, if nothing changes", p.rupees, tint: Ink.loss)
                Hair()
            }
            if let w = e.worstWeekday {
                LedgerRow("Worst day", "\(w.name.lowercased()) · \(w.missed)/\(w.total)")
                Hair()
            }
            LedgerRow("Cost of skipping one", e.rate.rupees)
        }
    }

    private func curve(_ e: GymEngine) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLabel(text: "How it added up")
            Chart(e.burnCurve, id: \.date) { p in
                AreaMark(x: .value("Date", p.date), y: .value("Lost", p.amount))
                    .foregroundStyle(
                        .linearGradient(colors: [Ink.loss.opacity(0.35), Ink.loss.opacity(0.01)],
                                        startPoint: .top, endPoint: .bottom)
                    )
                LineMark(x: .value("Date", p.date), y: .value("Lost", p.amount))
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .foregroundStyle(Ink.loss)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisValueLabel().font(.tight(13)).foregroundStyle(Ink.sub)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Ink.hair)
                    AxisValueLabel().font(.tight(13)).foregroundStyle(Ink.sub)
                }
            }
            .frame(height: 170)
        }
    }
}

// MARK: - Punch strip

struct PunchStrip: View {
    let days: [DayStatus]
    var onWhite: Bool

    private let columns = [GridItem(.adaptive(minimum: 32, maximum: 32), spacing: 10)]
    private var fg: Color { onWhite ? Ink.textL : Ink.text }
    private var future: Color { onWhite ? Ink.hairL : Color(white: 0.15) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                    Mark(day: d, fg: fg, future: future, index: i)
                        .frame(width: 32, height: 32)
                }
            }
            HStack(spacing: 20) {
                key(fill: fg, "went")
                key(stroke: Ink.loss, "missed")
                HStack(spacing: 7) {
                    Rectangle().fill(fg.opacity(0.45)).frame(width: 20, height: 5)
                    Text("excused").font(.tight(16)).foregroundStyle(onWhite ? Ink.subL : Ink.sub)
                }
            }
        }
    }

    private struct Mark: View {
        let day: DayStatus
        let fg: Color
        let future: Color
        let index: Int
        @State private var shown = false

        var body: some View {
            shape
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.5)
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)
                        .delay(Double(index) * 0.006)) { shown = true }
                }
        }

        @ViewBuilder private var shape: some View {
            if day.attended { Rectangle().fill(fg) }
            else if day.skipped { Rectangle().fill(fg.opacity(0.45)).frame(height: 5) }
            else if day.missed { Rectangle().strokeBorder(Ink.loss, lineWidth: 3) }
            else if day.isToday { Rectangle().strokeBorder(fg.opacity(0.8), lineWidth: 3) }
            else { Rectangle().strokeBorder(future, lineWidth: 2.4) }
        }
    }

    private func key(fill: Color? = nil, stroke: Color? = nil, _ label: String) -> some View {
        HStack(spacing: 7) {
            Group {
                if let fill { Rectangle().fill(fill) }
                else { Rectangle().strokeBorder(stroke ?? fg, lineWidth: 2.6) }
            }
            .frame(width: 20, height: 20)
            Text(label).font(.tight(16)).foregroundStyle(onWhite ? Ink.subL : Ink.sub)
        }
    }
}

// MARK: - Credit

struct CreditView: View {
    @ObservedObject var store: GymStore
    @State private var arc: Double = 0
    @State private var streak: Double = 0

    var body: some View {
        let e = store.engine
        Scaffold(onWhite: true, refresh: { store.reload() }) {
            ScreenHeader(
                title: "Credit",
                caption: "what you have earned",
                onWhite: true,
                trailing: AnyView(
                    Chip(text: e.canRepair ? "repairable" : "clean",
                         tint: e.canRepair ? Ink.warn : Ink.gain)
                )
            )
        } content: {
            VStack(spacing: 0) {
                if e.canRepair {
                    RepairCard(store: store, onWhite: true)
                        .padding(.horizontal, 24).padding(.top, 10)
                }

                hero(e).padding(.top, 22)
                bracket(e).padding(.top, 2)

                VStack(spacing: 0) {
                    SectionLabel(text: "Standing", onWhite: true).padding(.bottom, 4)
                    ledger(e)
                }
                .padding(.horizontal, 24)
                .padding(.top, 42)

                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionLabel(text: "The whole run", onWhite: true)
                        Text("\(e.wentCount) of \(e.timeline.filter { $0.scheduled }.count)")
                            .font(.figure(17))
                            .foregroundStyle(Ink.subL)
                    }
                    PunchStrip(days: e.timeline.filter { $0.scheduled }, onWhite: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 42)
            }
            .padding(.bottom, 150)
        }
        .onAppear {
            arc = 0; streak = 0
            withAnimation(.easeOut(duration: 1.1)) { arc = e.attendanceRate }
            withAnimation(.easeOut(duration: 0.9)) { streak = Double(e.currentStreak) }
        }
    }

    private func hero(_ e: GymEngine) -> some View {
        Gauge(progress: arc, tint: Ink.gain, track: Ink.hairL) {
            VStack(spacing: 4) {
                CountUp(value: streak, font: .figure(78, .heavy), color: Ink.gainDeep) {
                    String(Int($0.rounded()))
                }
                Text("session streak")
                    .font(.tight(18))
                    .foregroundStyle(Ink.subL)
                Text("\(Int((e.attendanceRate * 100).rounded()))% turned up")
                    .font(.tight(13))
                    .foregroundStyle(Ink.faintL)
                    .padding(.top, 6)
            }
        }
    }

    private func bracket(_ e: GymEngine) -> some View {
        VStack(spacing: 0) {
            Bracket()
                .stroke(Ink.hairL, lineWidth: 1)
                .frame(height: 28)
                .padding(.horizontal, 48)
            HStack(spacing: 0) {
                Pill(value: "\(e.longestStreak)", label: "longest",
                     tint: Ink.textL, stroke: Ink.faintL, labelTint: Ink.subL, delay: 0.05)
                Pill(value: e.justified.rupees, label: "earned back",
                     tint: Ink.gainDeep, stroke: Ink.gain.opacity(0.5), labelTint: Ink.gain, delay: 0.12)
                Pill(value: "\(e.perfectWeeks)", label: "perfect weeks",
                     tint: Ink.textL, stroke: Ink.faintL, labelTint: Ink.subL, delay: 0.19)
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)
        }
    }

    private func ledger(_ e: GymEngine) -> some View {
        VStack(spacing: 0) {
            if let d = e.daysSinceLastMiss {
                LedgerRow("Days since a miss", "\(d)", tint: Ink.textL, labelTint: Ink.subL)
                Hair(onWhite: true)
            }
            if let r = e.recoveryRate {
                LedgerRow("Bounced back", "\(Int((r * 100).rounded()))%",
                          tint: Ink.gainDeep, labelTint: Ink.subL)
                Hair(onWhite: true)
            }
            if let b = e.bestWeekday {
                LedgerRow("Best day", "\(b.name.lowercased()) · \(b.went)/\(b.total)",
                          tint: Ink.textL, labelTint: Ink.subL)
                Hair(onWhite: true)
            }
            LedgerRow("Sessions logged", "\(e.wentCount)", tint: Ink.textL, labelTint: Ink.subL)
        }
    }
}
