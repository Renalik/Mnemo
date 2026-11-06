import SwiftUI
import MnemoCore

struct MemoryOrb: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    var count: Int
    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || phase != .active || store.selectedTab != 0)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in draw(context: &context, size: size, time: time) }
            }.accessibilityHidden(true)
            VStack(spacing: 2) {
                Text("\(count)").font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                Text(store.t("карточек\nна сегодня", "cards\nfor today")).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Color(hex: store.theme.muted))
            }.frame(width: 138, height: 138).background {
                Circle().fill(Color(hex: store.theme.background).opacity(0.8)).glassEffect(.regular.tint(Color(hex: store.theme.accent).opacity(0.12)), in: .circle)
            }
        }.frame(height: 300).accessibilityElement(children: .combine)
    }
    private func draw(context: inout GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius: CGFloat = min(size.width, size.height) * 0.40
        let angle: Double = time * 0.13
        if store.settings.animation == "liquid" { drawLiquid(context: &context, center: center, radius: radius, angle: angle) }
        else if store.settings.animation == "cards" { drawCards(context: &context, center: center, angle: angle) }
        else { drawParticles(context: &context, center: center, radius: radius, angle: angle) }
    }
    private func drawLiquid(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, angle: Double) {
        for layer in 0..<4 {
            var path = Path()
            for i in 0...120 {
                let a = Double(i) * Double.pi * 2.0 / 120.0
                let wave = 0.8 + 0.07 * sin(a * 3 + angle * 5 + Double(layer)) + 0.06 * cos(a * 5 - angle * 3)
                let r = radius * CGFloat(wave)
                let point = CGPoint(x: center.x + CGFloat(cos(a)) * r, y: center.y + CGFloat(sin(a)) * r)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            context.stroke(path, with: .color(Color(hex: store.theme.accent).opacity(0.25 + Double(layer) * 0.12)), lineWidth: 1.5)
        }
    }
    private func drawCards(context: inout GraphicsContext, center: CGPoint, angle: Double) {
        for i in (0..<5).reversed() {
            var layer = context
            layer.translateBy(x: center.x, y: center.y + CGFloat(i) * 6)
            layer.rotate(by: .degrees(Double(i - 2) * 9 + sin(angle) * 5))
            let path = Path(roundedRect: CGRect(x: -72, y: -90, width: 144, height: 180), cornerRadius: 22)
            layer.fill(path, with: .color(Color(hex: store.theme.accent).opacity(0.08 + Double(5 - i) * 0.025)))
            layer.stroke(path, with: .color(Color(hex: store.theme.accent).opacity(0.6)), lineWidth: 1)
        }
    }
    private func drawParticles(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, angle: Double) {
        var particles: [(point: CGPoint, depth: Double, size: CGFloat)] = []
        for i in 0..<240 {
            let y: Double = 1.0 - 2.0 * Double(i) / 239.0
            let r: Double = sqrt(max(0.0, 1.0 - y * y))
            let theta: Double = Double(i) * Double.pi * (3.0 - sqrt(5.0)) + angle
            let x = cos(theta) * r, z = sin(theta) * r
            let tiltY = y * 0.92 - z * 0.38, tiltZ = y * 0.38 + z * 0.92
            let point: CGPoint
            if store.settings.animation == "galaxy" {
                let spiral = Double(i) / 240.0
                let a = spiral * Double.pi * 12 + angle
                point = CGPoint(x: center.x + CGFloat(cos(a) * sqrt(spiral)) * radius,
                                y: center.y + CGFloat(sin(a) * 0.55 * sqrt(spiral)) * radius)
            } else { point = CGPoint(x: center.x + CGFloat(x) * radius, y: center.y + CGFloat(tiltY) * radius) }
            particles.append((point, tiltZ, CGFloat(1.4 + (tiltZ + 1) * 1.4)))
        }
        for particle in particles.sorted(by: { $0.depth < $1.depth }) {
            let point = particle.point, r = particle.size, depth = particle.depth
            let color = depth < -0.5 ? Color(hex: store.theme.muted).opacity(0.3) : Color(hex: store.theme.accent).opacity(0.16 + (depth + 1) * 0.34)
            if depth > 0.7 { context.fill(Path(ellipseIn: CGRect(x: point.x - r * 2, y: point.y - r * 2, width: r * 4, height: r * 4)), with: .color(color.opacity(0.15))) }
            context.fill(Path(ellipseIn: CGRect(x: point.x - r / 2, y: point.y - r / 2, width: r, height: r)), with: .color(color))
        }
        var ring = context
        ring.translateBy(x: center.x, y: center.y); ring.rotate(by: .degrees(-22))
        let ellipse = CGRect(x: -radius * 1.15, y: -radius * 0.28, width: radius * 2.3, height: radius * 0.56)
        ring.stroke(Path(ellipseIn: ellipse), with: .color(Color(hex: store.theme.accent).opacity(0.55)), lineWidth: 0.7)
    }
}
