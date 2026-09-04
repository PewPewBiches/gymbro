import SwiftUI
import UIKit

// MARK: - Palette

enum Ink {
    static let black = Color.black
    static let paper = Color.white

    // Dark canvas
    static let text = Color.white
    static let sub = Color(white: 0.62)
    static let faint = Color(white: 0.30)
    static let hair = Color(white: 0.18)
    static let surface = Color(white: 0.08)

    // Light canvas
    static let textL = Color.black
    static let subL = Color(white: 0.38)
    static let faintL = Color(white: 0.72)
    static let hairL = Color(white: 0.90)
    static let surfaceL = Color(white: 0.96)

    // Signal
    static let loss = Color(red: 1.00, green: 0.27, blue: 0.21)
    static let gain = Color(red: 0.05, green: 0.60, blue: 0.40)
    static let gainDeep = Color(red: 0.02, green: 0.42, blue: 0.28)
    static let warn = Color(red: 1.00, green: 0.72, blue: 0.16)
}

// MARK: - Type

extension Font {
    /// Serif for figures. Money and counts.
    static func figure(_ size: CGFloat, _ w: Font.Weight = .bold) -> Font {
        .system(size: size, weight: w, design: .serif)
    }
    /// Condensed sans for everything that is not a number.
    static func tight(_ size: CGFloat, _ w: Font.Weight = .medium) -> Font {
        .system(size: size, weight: w).width(.condensed)
    }
}

extension Double {
    var grouped: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_IN")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: self)) ?? "0"
    }
    var rupees: String { "₹" + grouped }
}

enum Haptic {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Counting figure

/// Animates through the intermediate values so the number rolls up
/// on appear instead of snapping into place.
struct CountUp: View, Animatable {
    var value: Double
    var font: Font
    var color: Color
    var format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }
}

// MARK: - Gauge

struct Gauge<Content: View>: View {
    var progress: Double
    var tint: Color
    var track: Color
    var size: CGFloat = 236
    var width: CGFloat = 9
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(track, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * max(0, min(1, progress)))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .shadow(color: tint.opacity(0.45), radius: 10)
            content
        }
        .frame(width: size, height: size)
    }
}

/// Thin rule dropping from the figure to three secondary metrics.
struct Bracket: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let mid = r.height * 0.5
        p.move(to: CGPoint(x: r.midX, y: 0))
        p.addLine(to: CGPoint(x: r.midX, y: mid))
        let third = r.width / 3
        let xs = [third * 0.5, third * 1.5, third * 2.5]
        p.move(to: CGPoint(x: xs[0], y: mid))
        p.addLine(to: CGPoint(x: xs[2], y: mid))
        for x in xs {
            p.move(to: CGPoint(x: x, y: mid))
            p.addLine(to: CGPoint(x: x, y: r.height))
        }
        return p
    }
}

struct Pill: View {
    let value: String
    let label: String
    var tint: Color
    var stroke: Color
    var labelTint: Color
    var delay: Double = 0

    @State private var shown = false

    var body: some View {
        VStack(spacing: 9) {
            Text(value)
                .font(.figure(24))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(stroke.opacity(0.10)))
                .overlay(Capsule().stroke(stroke, lineWidth: 1.4))
            Text(label)
                .font(.tight(15))
                .foregroundStyle(labelTint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 14)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(delay)) {
                shown = true
            }
        }
    }
}

// MARK: - Rows

struct LedgerRow: View {
    let label: String
    let value: String
    var tint: Color = Ink.text
    var labelTint: Color = Ink.sub

    init(_ label: String, _ value: String, tint: Color = Ink.text, labelTint: Color = Ink.sub) {
        self.label = label; self.value = value; self.tint = tint; self.labelTint = labelTint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.tight(17))
                .foregroundStyle(labelTint)
            Spacer(minLength: 16)
            Text(value)
                .font(.figure(21))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 16)
    }
}

struct Hair: View {
    var onWhite = false
    var body: some View {
        Rectangle()
            .fill(onWhite ? Ink.hairL : Ink.hair)
            .frame(height: 1)
    }
}

/// Section label. Sits above a block, never inside a card.
struct SectionLabel: View {
    let text: String
    var onWhite = false
    var body: some View {
        Text(text)
            .font(.tight(15, .semibold))
            .foregroundStyle(onWhite ? Ink.subL : Ink.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Screen header

struct ScreenHeader: View {
    let title: String
    let caption: String
    var onWhite = false
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.tight(15, .semibold))
                    .foregroundStyle(onWhite ? Ink.subL : Ink.sub)
                Text(title)
                    .font(.figure(32, .heavy))
                    .foregroundStyle(onWhite ? Ink.textL : Ink.text)
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// Small status chip, e.g. "gym day" or "rest day".
struct Chip: View {
    let text: String
    var tint: Color
    var body: some View {
        Text(text)
            .font(.tight(14, .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Tab bar

struct FloatingBar: View {
    @Binding var tab: Int
    /// True when the screen behind is white, so the bar flips to black.
    var onWhite: Bool
    @Namespace private var ns

    private let items: [(String, String)] = [
        ("Burnt", "flame.fill"),
        ("Days", "calendar"),
        ("Setup", "slider.horizontal.3"),
        ("Credit", "checkmark.seal.fill")
    ]

    private var barFill: Color { onWhite ? Ink.black : Ink.paper }
    private var pillFill: Color { onWhite ? Ink.paper : Ink.black }
    private var selectedInk: Color { onWhite ? Ink.black : Ink.paper }
    private var idleInk: Color { onWhite ? Color(white: 0.55) : Color(white: 0.42) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    Haptic.tap()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { tab = i }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: items[i].1)
                            .font(.system(size: 16, weight: .semibold))
                        Text(items[i].0)
                            .font(.tight(13, .semibold))
                    }
                    .foregroundStyle(tab == i ? selectedInk : idleInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if tab == i {
                            Capsule()
                                .fill(pillFill)
                                .matchedGeometryEffect(id: "sel", in: ns)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(barFill))
        .shadow(color: .black.opacity(onWhite ? 0.22 : 0.45), radius: 20, y: 8)
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.3), value: onWhite)
    }
}

// MARK: - Scroll aware scaffold

private struct ScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Pins the screen header and slides a blur under it once the content
/// starts passing behind, so nothing ever collides with the status bar.
struct Scaffold<Header: View, Content: View>: View {
    var onWhite: Bool = false
    var refresh: (() -> Void)? = nil
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0

    private var collapsed: Bool { offset < -6 }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(
                                key: ScrollKey.self,
                                value: g.frame(in: .named("scroll")).minY
                            )
                        }
                    )
                content
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollKey.self) { offset = $0 }
        .refreshable { refresh?() }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .background {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Rectangle().fill((onWhite ? Ink.paper : Ink.black).opacity(0.6))
                    }
                    .opacity(collapsed ? 1 : 0)
                    .ignoresSafeArea(edges: .top)
                }
                .overlay(alignment: .bottom) {
                    Hair(onWhite: onWhite).opacity(collapsed ? 1 : 0)
                }
                .animation(.easeOut(duration: 0.22), value: collapsed)
        }
    }
}
