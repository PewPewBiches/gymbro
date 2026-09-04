import SwiftUI

/// Shown once, when the folder is linked but there is no config yet.
/// Nobody should have to open a code file to use this.
struct OnboardingView: View {
    @ObservedObject var store: GymStore

    @State private var step = 0
    @State private var fee: Double = 10000
    @State private var months = 4
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var days: Set<Int> = [2, 3, 4, 5, 6]   // Mon to Fri
    @State private var minMinutes = 45
    @FocusState private var feeFocused: Bool

    private let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private let lastStep = 4

    var body: some View {
        ZStack {
            Ink.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                progress.padding(.top, 12)

                ZStack(alignment: .topLeading) {
                    switch step {
                    case 0: intro.transition(slide)
                    case 1: moneyStep.transition(slide)
                    case 2: dateStep.transition(slide)
                    case 3: daysStep.transition(slide)
                    default: minutesStep.transition(slide)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                footer
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 20)
        }
        .preferredColorScheme(.dark)
    }

    private var slide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: Chrome

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0...lastStep, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Ink.paper : Ink.hair)
                    .frame(height: 4)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            if step == lastStep {
                summary
            }

            HStack(spacing: 12) {
                if step > 0 {
                    Button {
                        Haptic.tap()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Ink.text)
                            .frame(width: 58, height: 58)
                            .background(Circle().stroke(Ink.hair, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    feeFocused = false
                    Haptic.tap(.medium)
                    if step == lastStep {
                        finish()
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step += 1 }
                    }
                } label: {
                    Text(step == lastStep ? "Start burning" : "Continue")
                        .font(.tight(19, .bold))
                        .foregroundStyle(Ink.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 19)
                        .background(Capsule().fill(Ink.paper))
                }
                .buttonStyle(.plain)
                .disabled(step == 3 && days.isEmpty)
                .opacity(step == 3 && days.isEmpty ? 0.4 : 1)
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 6) {
            Text("Each session you skip will cost you")
                .font(.tight(15))
                .foregroundStyle(Ink.sub)
            Text(rate.rupees)
                .font(.figure(46, .heavy))
                .foregroundStyle(Ink.loss)
            Text("\(scheduledCount) sessions between \(fmt(start)) and \(fmt(end))")
                .font(.tight(14))
                .foregroundStyle(Ink.faint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Ink.loss.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Ink.loss.opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: Steps

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 30)
            Text("You already paid for this")
                .font(.figure(40, .heavy))
                .foregroundStyle(Ink.text)

            Text("gymbro splits your membership fee across the days you planned to train. Every session you skip has a price, and this puts that number somewhere you cannot avoid it.")
                .font(.tight(18))
                .foregroundStyle(Ink.sub)

            Text("Four questions and you are done. You can change any of it later.")
                .font(.tight(16))
                .foregroundStyle(Ink.faint)
            Spacer()
        }
    }

    private var moneyStep: some View {
        VStack(alignment: .leading, spacing: 26) {
            question("What did you pay?", "The full membership fee.")

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("₹")
                    .font(.figure(34))
                    .foregroundStyle(Ink.faint)
                TextField("10000", value: $fee, format: .number)
                    .keyboardType(.numberPad)
                    .font(.figure(44, .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Ink.text)
                    .focused($feeFocused)
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) { Hair() }

            VStack(alignment: .leading, spacing: 12) {
                Text("How many months does it cover?")
                    .font(.tight(17))
                    .foregroundStyle(Ink.sub)
                HStack(spacing: 10) {
                    ForEach([1, 3, 6, 12], id: \.self) { m in
                        chip("\(m)", selected: months == m) { months = m }
                    }
                    chip("4", selected: months == 4) { months = 4 }
                }
            }
            Spacer()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { feeFocused = false }.font(.tight(18, .bold))
            }
        }
    }

    private var dateStep: some View {
        VStack(alignment: .leading, spacing: 26) {
            question("When did it start?", "The first day of the membership, not today.")

            DatePicker("", selection: $start, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Ink.paper)
                .labelsHidden()

            Text("Ends \(fmt(end))")
                .font(.tight(16))
                .foregroundStyle(Ink.faint)
            Spacer()
        }
    }

    private var daysStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            question("Which days do you train?", "Only these cost you money. Rest days are free.")

            VStack(spacing: 0) {
                ForEach(1...7, id: \.self) { d in
                    DayToggle(name: names[d - 1], on: Binding(
                        get: { days.contains(d) },
                        set: { on in if on { days.insert(d) } else { days.remove(d) } }
                    ))
                    if d < 7 { Hair() }
                }
            }
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Ink.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Ink.hair, lineWidth: 1)
                    )
            )
            Spacer()
        }
    }

    private var minutesStep: some View {
        VStack(alignment: .leading, spacing: 26) {
            question("How short is your shortest visit?",
                     "Anything shorter gets treated as walking past.")

            HStack {
                Spacer()
                Stepper2(value: $minMinutes, range: 0...180, step: 5)
                Spacer()
            }

            Text("Set it a little under your real shortest session. Better to occasionally credit a short visit than have a real one silently not count.")
                .font(.tight(15))
                .foregroundStyle(Ink.faint)
            Spacer()
        }
    }

    // MARK: Pieces

    private func question(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.figure(32, .heavy))
                .foregroundStyle(Ink.text)
            Text(sub)
                .font(.tight(17))
                .foregroundStyle(Ink.sub)
        }
        .padding(.top, 26)
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.easeOut(duration: 0.15)) { action() }
        } label: {
            Text(label)
                .font(.figure(20, .bold))
                .foregroundStyle(selected ? Ink.black : Ink.text)
                .frame(width: 58, height: 52)
                .background(Capsule().fill(selected ? Ink.paper : Ink.surface))
                .overlay(Capsule().stroke(selected ? .clear : Ink.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Maths

    private var end: Date {
        Calendar.current.date(byAdding: .month, value: months, to: start) ?? start
    }

    private var scheduledCount: Int {
        var n = 0
        var d = start
        let cal = Calendar.current
        while d <= end {
            if days.contains(cal.component(.weekday, from: d)) { n += 1 }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? end.addingTimeInterval(1)
        }
        return n
    }

    private var rate: Double {
        scheduledCount > 0 ? fee / Double(scheduledCount) : 0
    }

    private func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    private func finish() {
        let today = GymDate.key(GymDate.today())
        let config = GymConfig(
            start: GymDate.key(start),
            end: GymDate.key(end),
            totalFee: fee,
            days: days.sorted(),
            minMinutes: minMinutes,
            // Start counting from today, so days before install are not charged.
            trackFrom: max(GymDate.key(start), today),
            seedMissed: 0,
            skipDates: [],
            restored: []
        )
        store.completeSetup(config)
        Haptic.success()
    }
}
