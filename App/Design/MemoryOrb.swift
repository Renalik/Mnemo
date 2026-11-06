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
                Canvas { context, size in
                    let c = CGPoint(x: size.width/2, y: size.height/2), radius = min(size.width, size.height) * 0.40
                    let angle = time * 0.13
                    if store.settings.animation == "liquid" {
                        for layer in 0..<4 {
                            var path = Path()
                            for i in 0...120 {
                                let a = Double(i) * .pi * 2 / 120
                                let r = radius * (0.8 + 0.07 * sin(a*3 + angle*5 + Double(layer)) + 0.06 * cos(a*5 - angle*3))
                                let p = CGPoint(x: c.x + cos(a)*r, y: c.y + sin(a)*r)
                                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                            }
                            path.closeSubpath()
                            context.stroke(path, with: .color(Color(hex: store.theme.accent).opacity(0.25 + Double(layer)*0.12)), lineWidth: 1.5)
                        }
                    } else if store.settings.animation == "cards" {
                        for i in (0..<5).reversed() {
                            var layer = context
                            layer.translateBy(x: c.x, y: c.y + CGFloat(i) * 6)
                            layer.rotate(by: .degrees(Double(i-2)*9 + sin(angle)*5))
                            let rect = CGRect(x: -72, y: -90, width: 144, height: 180)
                            let path = Path(roundedRect: rect, cornerRadius: 22)
                            layer.fill(path, with: .color(Color(hex: store.theme.accent).opacity(0.08 + Double(5-i)*0.025)))
                            layer.stroke(path, with: .color(Color(hex: store.theme.accent).opacity(0.6)), lineWidth: 1)
                        }
                    } else {
                        var particles: [(CGPoint, Double, CGFloat)] = []
                        for i in 0..<240 {
                            let y = 1 - 2 * Double(i) / 239
                            let r = sqrt(max(0, 1-y*y))
                            let theta = Double(i) * .pi * (3-sqrt(5)) + angle
                            let x = cos(theta)*r, z = sin(theta)*r
                            let tiltY = y * 0.92 - z * 0.38, tiltZ = y * 0.38 + z * 0.92
                            let p: CGPoint
                            if store.settings.animation == "galaxy" {
                                let spiral = Double(i) / 240
                                let a = spiral * .pi * 12 + angle
                                p = CGPoint(x: c.x + cos(a)*radius*sqrt(spiral), y: c.y + sin(a)*radius*0.55*sqrt(spiral))
                            } else { p = CGPoint(x: c.x + x*radius, y: c.y + tiltY*radius) }
                            particles.append((p, tiltZ, CGFloat(1.4 + (tiltZ+1)*1.4)))
                        }
                        for (p,z,r) in particles.sorted(by: { $0.1 < $1.1 }) {
                            let color = Color(hex: store.theme.accent).opacity(0.16 + (z+1)*0.34)
                            if z > 0.7 { context.fill(Path(ellipseIn: CGRect(x: p.x-r*2, y: p.y-r*2, width: r*4, height: r*4)), with: .color(color.opacity(0.15))) }
                            context.fill(Path(ellipseIn: CGRect(x: p.x-r/2, y: p.y-r/2, width: r, height: r)), with: .color(iColor(z, color: color)))
                        }
                        var ring = context
                        ring.translateBy(x: c.x, y: c.y); ring.rotate(by: .degrees(-22))
                        ring.stroke(Path(ellipseIn: CGRect(x: -radius*1.15, y: -radius*0.28, width: radius*2.3, height: radius*0.56)), with: .color(Color(hex: store.theme.accent).opacity(0.55)), lineWidth: 0.7)
                    }
                }
            }.accessibilityHidden(true)
            VStack(spacing: 2) {
                Text("\(count)").font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                Text(store.t("карточек\nна сегодня", "cards\nfor today")).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Color(hex: store.theme.muted))
            }.frame(width: 138, height: 138).background {
                Circle().fill(Color(hex: store.theme.background).opacity(0.8)).glassEffect(.regular.tint(Color(hex: store.theme.accent).opacity(0.12)), in: .circle)
            }
        }.frame(height: 300).accessibilityElement(children: .combine)
    }
    private func iColor(_ z: Double, color: Color) -> Color { z < -0.5 ? Color(hex: store.theme.muted).opacity(0.3) : color }
}
