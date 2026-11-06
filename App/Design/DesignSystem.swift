import SwiftUI
import MnemoCore

extension Color {
    init(hex: String) {
        let n = UInt64(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255, opacity: 1)
    }
}

enum Space {
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let section: CGFloat = 32
    static let menuScrollClearance: CGFloat = 96
}

extension View {
    func mainMenuClearance() -> some View {
        contentMargins(.bottom, Space.menuScrollClearance, for: .scrollContent)
    }
}

struct AmbientBackground: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: store.theme.background)
                Ellipse().fill(Color(hex: store.theme.glow).opacity(store.theme.dark ? 0.7 : 0.35))
                    .frame(width: geometry.size.width * 1.1, height: geometry.size.height * 0.65)
                    .blur(radius: 85).offset(x: geometry.size.width * 0.45, y: -geometry.size.height * 0.3)
                Ellipse().fill(Color(hex: store.theme.accent).opacity(store.theme.dark ? 0.18 : 0.12))
                    .frame(width: geometry.size.width * 1.2, height: 270).blur(radius: 60)
                    .offset(x: -geometry.size.width * 0.45, y: geometry.size.height * 0.3)
                Canvas { context, size in
                    for index in 0..<8 {
                        let y = size.height * 0.78 + CGFloat(index) * 14
                        let rect = CGRect(x: -90, y: y, width: size.width + 180, height: 180)
                        context.stroke(Path(ellipseIn: rect), with: .color(Color(hex: store.theme.accent).opacity(0.025 + Double(index) * 0.003)), lineWidth: 2)
                    }
                }.blur(radius: 2)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct GlassPanel<Content: View>: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        Group {
            if reduceTransparency {
                content.padding(padding).background(Color(hex: store.theme.dark ? "222124" : "FFFFFF"), in: RoundedRectangle(cornerRadius: 28))
            } else {
                content.padding(padding).glassEffect(.regular, in: .rect(cornerRadius: 28))
            }
        }
    }
}

struct PrimaryButton: View {
    @Environment(AppStore.self) private var store
    let title: String
    var symbol: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol { Image(systemName: symbol) }
                Text(title).font(.system(.headline, design: .rounded))
            }.frame(maxWidth: .infinity).padding(.vertical, 17)
                .foregroundStyle(Color(hex: store.theme.buttonText))
                .background(LinearGradient(colors: [Color(hex: store.theme.accent).opacity(0.9), Color(hex: store.theme.accent)], startPoint: .top, endPoint: .bottom), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
                .shadow(color: Color(hex: store.theme.accent).opacity(0.25), radius: 18, y: 8)
        }.buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 21, weight: .medium)).frame(width: 48, height: 48) }
            .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel(label)
    }
}

struct SectionTitle: View {
    @Environment(AppStore.self) private var store
    let title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.title3, design: .rounded, weight: .bold))
            Spacer(minLength: 8)
            if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(Color(hex: store.theme.muted)) }
        }.accessibilityAddTraits(.isHeader)
    }
}

struct Metric: View {
    @Environment(AppStore.self) private var store
    let value: String
    let label: String
    var detail = ""
    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 7) {
                Text(value).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                Text(label).font(.subheadline).foregroundStyle(Color(hex: store.theme.muted))
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(Color(hex: store.theme.muted)) }
            }.frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }
}

struct EmptyMessage: View {
    @Environment(AppStore.self) private var store
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(Color(hex: store.theme.accent))
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Text(detail).font(.subheadline).foregroundStyle(Color(hex: store.theme.muted)).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}

struct ProgressRing: View {
    @Environment(AppStore.self) private var store
    var value: Double
    var size: CGFloat = 76
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.12), lineWidth: 7)
            Circle().trim(from: 0, to: min(1, max(0, value))).stroke(Color(hex: store.theme.accent), style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(value.formatted(.percent.precision(.fractionLength(0)))).font(.system(size: size * 0.25, weight: .bold, design: .rounded)).monospacedDigit()
        }.frame(width: size, height: size).accessibilityLabel(value.formatted(.percent))
    }
}

struct Segments: View {
    @Environment(AppStore.self) private var store
    @Binding var selected: Int
    let labels: [String]
    @Namespace private var namespace
    var body: some View {
        HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { selected = index }
                    Haptics.tap(store.settings.haptics)
                } label: {
                    Text(labels[index]).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected == index { Capsule().fill(.primary.opacity(0.12)).matchedGeometryEffect(id: "segment", in: namespace) }
                        }.contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(selected == index ? .isSelected : [])
            }
        }.padding(4).glassEffect(in: .capsule)
    }
}

struct SettingRow<Accessory: View>: View {
    @Environment(AppStore.self) private var store
    let symbol: String
    let title: String
    @ViewBuilder var accessory: Accessory
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(Color(hex: store.theme.accent))
                .frame(width: 38, height: 40).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            Text(title).font(.body)
            Spacer(minLength: 4)
            accessory
        }.frame(minHeight: 48).contentShape(Rectangle())
    }
}

struct DeckMark: View {
    let deck: Deck
    var size: CGFloat = 42
    var body: some View {
        CardSurface(themeID: deck.themeID)
            .overlay { Text(String(deck.name.prefix(2)).uppercased()).font(.system(size: size * 0.34, weight: .bold, design: .rounded)).foregroundStyle(Color(hex: CardTheme(id: deck.themeID).text)) }
            .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}
