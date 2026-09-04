import SwiftUI

struct SetupView: View {
    @ObservedObject var store: GymStore
    @State private var draft: GymConfig = .fallback
    @State private var loaded = false
    @State private var saved = false
    @FocusState private var amountFocused: Bool

    private let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private var dirty: Bool { draft != store.config }

    var body: some View {
        Scaffold(onWhite: false) {
            ScreenHeader(
                title: "Setup",
                caption: "change anything, any time",
                trailing: dirty ? AnyView(Chip(text: "unsaved", tint: Ink.warn)) : nil
            )
        } content: {
            VStack(spacing: 34) {
                block("Membership") {
                    HStack {
                        Text("Amount paid").font(.tight(17)).foregroundStyle(Ink.sub)
                        Spacer()
                        Text("\u{20B9}").font(.figure(21)).foregroundStyle(Ink.faint)
                        TextField("10000", value: $draft.totalFee, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.figure(23, .bold))
                            .monospacedDigit()
                            .foregroundStyle(Ink.text)
                            .focused($amountFocused)
                            .frame(maxWidth: 130)
                    }
                    .padding(.vertical, 15)

                    Hair()

                    dateRow("Starts", \.start)
                    Hair()
                    dateRow("Ends", \.end)
                }

                block("Days you go") {
                    ForEach(1...7, id: \.self) { d in
                        DayToggle(name: names[d - 1], on: dayBinding(d))
                        if d < 7 { Hair() }
                    }
                }

                block("What counts as a session") {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Minimum stay").font(.tight(17)).foregroundStyle(Ink.sub)
                            Text("Anything shorter gets treated as walking past")
                                .font(.tight(14)).foregroundStyle(Ink.faint)
                        }
                        Spacer()
                        Stepper2(value: $draft.minMinutes, range: 0...180, step: 5)
                    }
                    .padding(.vertical, 15)
                }

                block("Result") {
                    LedgerRow("Each missed session",
                              GymEngine(config: draft, entries: []).rate.rupees,
                              tint: Ink.loss)
                    Hair()
                    LedgerRow("Excused days", "\(draft.skipDates.count)")
                }

                saveButton

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Folder").font(.tight(16)).foregroundStyle(Ink.faint)
                        Spacer()
                        Text(store.folderName ?? "not linked")
                            .font(.tight(16)).foregroundStyle(Ink.sub)
                    }
                    Button {
                        Haptic.tap()
                        store.reload(); draft = store.config
                    } label: {
                        Text("Reload from disk")
                            .font(.tight(16, .semibold))
                            .foregroundStyle(Ink.sub)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 160)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { amountFocused = false }.font(.tight(18, .bold))
            }
        }
        .onAppear { if !loaded { draft = store.config; loaded = true } }
    }

    // MARK: Pieces

    @ViewBuilder
    private func block<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Ink.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Ink.hair, lineWidth: 1)
                        )
                )
        }
    }

    private func dateRow(_ label: String, _ path: WritableKeyPath<GymConfig, String>) -> some View {
        HStack {
            Text(label).font(.tight(17)).foregroundStyle(Ink.sub)
            Spacer()
            DatePicker("", selection: dateBinding(path), displayedComponents: .date)
                .labelsHidden()
                .tint(Ink.paper)
        }
        .padding(.vertical, 11)
    }

    private var saveButton: some View {
        Button {
            amountFocused = false
            store.saveConfig(draft)
            Haptic.success()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { saved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { saved = false }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: saved ? "checkmark" : "arrow.down.to.line")
                    .font(.system(size: 16, weight: .bold))
                Text(saved ? "Saved" : "Save changes")
                    .font(.tight(19, .bold))
            }
            .foregroundStyle(dirty || saved ? Ink.black : Ink.faint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule().fill(saved ? Ink.gain : (dirty ? Ink.paper : Ink.surface))
            )
            .overlay(Capsule().stroke(dirty || saved ? .clear : Ink.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!dirty)
        .animation(.easeOut(duration: 0.2), value: dirty)
    }

    private func dayBinding(_ d: Int) -> Binding<Bool> {
        Binding(
            get: { draft.days.contains(d) },
            set: { on in
                if on { draft.days.append(d); draft.days.sort() }
                else { draft.days.removeAll { $0 == d } }
            }
        )
    }

    private func dateBinding(_ path: WritableKeyPath<GymConfig, String>) -> Binding<Date> {
        Binding(
            get: { GymDate.date(draft[keyPath: path]) ?? Date() },
            set: { draft[keyPath: path] = GymDate.key($0) }
        )
    }
}

// MARK: - Controls

/// Switch that turns green when on, so it reads as active rather than
/// as a white slab.
struct DayToggle: View {
    let name: String
    @Binding var on: Bool

    var body: some View {
        HStack {
            Text(name)
                .font(.tight(18, on ? .semibold : .regular))
                .foregroundStyle(on ? Ink.text : Ink.sub)
            Spacer()
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? Ink.gain : Color(white: 0.20))
                    .frame(width: 52, height: 31)
                Circle()
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .padding(.horizontal, 3)
            }
            .frame(width: 52, height: 31)
            .onTapGesture {
                Haptic.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { on.toggle() }
            }
        }
        .padding(.vertical, 13)
    }
}

struct Stepper2: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 0) {
            button("minus") {
                value = max(range.lowerBound, value - step)
            }
            Text("\(value)m")
                .font(.figure(20, .bold))
                .monospacedDigit()
                .foregroundStyle(Ink.text)
                .frame(width: 62)
                .contentTransition(.numericText())
            button("plus") {
                value = min(range.upperBound, value + step)
            }
        }
        .background(Capsule().fill(Color(white: 0.14)))
        .overlay(Capsule().stroke(Ink.hair, lineWidth: 1))
    }

    private func button(_ icon: String, _ run: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.easeOut(duration: 0.18)) { run() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Ink.text)
                .frame(width: 44, height: 42)
        }
        .buttonStyle(.plain)
    }
}
