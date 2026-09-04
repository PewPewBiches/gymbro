import SwiftUI

/// Offered, never applied automatically. You broke the streak at midnight
/// and this is the chance to buy it back with a session you actually did.
struct RepairCard: View {
    @ObservedObject var store: GymStore
    var onWhite: Bool = false
    @State private var sheet = false
    @State private var pulse = false

    private var text: Color { onWhite ? Ink.textL : Ink.text }
    private var sub: Color { onWhite ? Ink.subL : Ink.sub }

    var body: some View {
        let items = store.engine.repairable
        Button {
            Haptic.tap()
            sheet = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Ink.warn.opacity(0.22)).frame(width: 44, height: 44)
                        .scaleEffect(pulse ? 1.18 : 1)
                        .opacity(pulse ? 0 : 1)
                    Circle().fill(Ink.warn.opacity(0.18)).frame(width: 44, height: 44)
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Ink.warn)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(items.count == 1 ? "One day can be repaired" : "\(items.count) days can be repaired")
                        .font(.tight(19, .bold))
                        .foregroundStyle(text)
                    Text("You trained a weekend. Spend it to undo the break.")
                        .font(.tight(16))
                        .foregroundStyle(sub)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Ink.warn)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Ink.warn.opacity(onWhite ? 0.16 : 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Ink.warn.opacity(0.55), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .sheet(isPresented: $sheet) {
            RepairSheet(store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Ink.surface)
        }
    }
}

struct RepairSheet: View {
    @ObservedObject var store: GymStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = store.engine.repairable
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("repair the streak")
                        .font(.tight(15, .semibold))
                        .foregroundStyle(Ink.sub)
                    Text("Spend a weekend session")
                        .font(.figure(30, .heavy))
                        .foregroundStyle(Ink.text)
                    Text("Each weekend session you logged can undo one broken weekday in the same week. The money for that day comes back too, because you did the work.")
                        .font(.tight(16))
                        .foregroundStyle(Ink.sub)
                        .padding(.top, 4)
                }
                .padding(.top, 26)

                if items.isEmpty {
                    Text("Nothing to repair right now.")
                        .font(.tight(17))
                        .foregroundStyle(Ink.faint)
                } else {
                    VStack(spacing: 10) {
                        ForEach(items, id: \.day.id) { item in
                            row(item.day, tokens: item.tokensLeft)
                        }
                    }
                }

                if store.engine.spareTokens > 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Ink.gain)
                        Text("\(store.engine.spareTokens) spare weekend session banked for this week.")
                            .font(.tight(15))
                            .foregroundStyle(Ink.sub)
                    }
                    .padding(.top, 4)
                }

                if !store.config.restored.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Already repaired")
                        ForEach(store.config.restored.reversed(), id: \.self) { k in
                            if let d = GymDate.date(k) {
                                undoRow(d)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func row(_ day: DayStatus, tokens: Int) -> some View {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"
        return Button {
            store.repair(day.date)
            Haptic.success()
            if store.engine.repairable.isEmpty { dismiss() }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(f.string(from: day.date))
                        .font(.tight(18, .bold))
                        .foregroundStyle(Ink.text)
                    Text(day.skipped ? "excused, streak still broken" : "missed")
                        .font(.tight(15))
                        .foregroundStyle(Ink.loss.opacity(0.9))
                }
                Spacer()
                Text("Repair")
                    .font(.tight(17, .bold))
                    .foregroundStyle(Ink.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Ink.warn))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Ink.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Ink.hair, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func undoRow(_ date: Date) -> some View {
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return HStack {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .foregroundStyle(Ink.gain)
            Text(f.string(from: date))
                .font(.tight(17))
                .foregroundStyle(Ink.text)
            Spacer()
            Button {
                store.unrepair(date)
                Haptic.tap(.medium)
            } label: {
                Text("Undo")
                    .font(.tight(16, .semibold))
                    .foregroundStyle(Ink.sub)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}
