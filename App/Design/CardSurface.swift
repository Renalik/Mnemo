import SwiftUI
import MnemoCore

struct CardSurface: View {
    let themeID: Int
    private var theme: CardTheme { CardTheme(id: max(0, min(149, themeID))) }
    var body: some View {
        GeometryReader { geometry in
            let base = Color(hex: theme.palette.hex)
            ZStack {
                base
                switch theme.category {
                case 1:
                    LinearGradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                case 4:
                    AngularGradient(colors: multicolor, center: theme.variant == 1 ? .bottomLeading : .center, angle: .degrees(Double(theme.id * 17)))
                    if theme.variant != 3 { Rectangle().fill(.white.opacity(0.15)).blur(radius: 20) }
                default: EmptyView()
                }
                if theme.category >= 2 && theme.category != 4 {
                    Canvas { context, size in draw(context: &context, size: size) }
                }
                LinearGradient(colors: [.white.opacity(0.14), .clear, .black.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
    }
    private var multicolor: [Color] {
        switch theme.variant {
        case 0: return [.yellow, .cyan, .indigo, .purple, .yellow]
        case 1: return [.pink, .white, Color(hex: theme.palette.hex), .cyan, .pink]
        case 2: return [Color(hex: theme.palette.hex), .blue.opacity(0.7), .mint, .pink, Color(hex: theme.palette.hex)]
        case 3: return [Color(hex: theme.palette.hex), .orange, .indigo, .orange, Color(hex: theme.palette.hex), .black, .indigo]
        default: return [Color(hex: "FFF8C1"), Color(hex: "C9F4FC"), Color(hex: "E2CFFF"), Color(hex: "FFDCE7"), Color(hex: "FFF8C1")]
        }
    }
    private func draw(context: inout GraphicsContext, size: CGSize) {
        let step: CGFloat = max(15, min(size.width, size.height) / 7)
        let ink = Color(hex: theme.text).opacity(theme.category == 5 ? 0.10 : 0.19)
        if theme.category == 2 {
            switch theme.variant {
            case 0:
                for x in stride(from: step / 2, through: size.width, by: step) {
                    for y in stride(from: step / 2, through: size.height, by: step) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: step * 0.14, height: step * 0.14)), with: .color(ink))
                    }
                }
            case 1:
                for x in stride(from: -size.height, through: size.width, by: step) {
                    var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + size.height, y: size.height)); context.stroke(p, with: .color(ink), lineWidth: step * 0.45)
                }
            case 2, 4:
                for x in stride(from: CGFloat(0), through: size.width, by: step) {
                    for y in stride(from: CGFloat(0), through: size.height, by: step) {
                        let rect = CGRect(x: x, y: y, width: step, height: step)
                        if theme.variant == 4 && (Int(x / step) + Int(y / step)).isMultiple(of: 2) { context.fill(Path(rect), with: .color(ink)) }
                        else if theme.variant == 2 { context.stroke(Path(rect), with: .color(ink), lineWidth: 0.8) }
                    }
                }
            default:
                for y in stride(from: CGFloat(-step), through: size.height + step, by: step * 0.7) {
                    for x in stride(from: CGFloat(-step), through: size.width + step, by: step) {
                        var p = Path()
                        p.addArc(center: CGPoint(x: x + step / 2, y: y), radius: step * 0.48, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                        p.addArc(center: CGPoint(x: x + step / 2, y: y + step * 0.45), radius: step * 0.48, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                        context.stroke(p, with: .color(ink), lineWidth: step * 0.12)
                    }
                }
            }
        } else if theme.category == 3 {
            switch theme.variant {
            case 0, 4:
                for y in stride(from: CGFloat(0), through: size.height, by: step) {
                    for x in stride(from: CGFloat(0), through: size.width, by: step) {
                        var p = Path()
                        if theme.variant == 0 {
                            p.move(to: CGPoint(x: x, y: y + step/2)); p.addLine(to: CGPoint(x: x+step/2, y: y)); p.addLine(to: CGPoint(x: x+step, y: y+step/2)); p.addLine(to: CGPoint(x: x+step/2, y: y+step))
                        } else {
                            p.move(to: CGPoint(x: x, y: y+step)); p.addLine(to: CGPoint(x: x+step/2, y: y)); p.addLine(to: CGPoint(x: x+step, y: y+step))
                        }
                        p.closeSubpath(); context.fill(p, with: .color(ink))
                    }
                }
            case 1:
                for y in stride(from: CGFloat(-step), through: size.height, by: step) {
                    var p = Path(); p.move(to: CGPoint(x: -step, y: y))
                    for index in 0...Int(size.width / (step / 2)) + 2 { p.addLine(to: CGPoint(x: CGFloat(index) * step / 2, y: y + (index.isMultiple(of: 2) ? 0 : step / 2))) }
                    context.stroke(p, with: .color(ink), lineWidth: step * 0.4)
                }
            case 2:
                for i in 0..<30 {
                    let angle = Double(i) * Double.pi * 2 / 30
                    var p = Path(); p.move(to: CGPoint(x: 0, y: size.height))
                    p.addLine(to: CGPoint(x: cos(angle) * size.height * 3, y: size.height + sin(angle) * size.height * 3))
                    context.stroke(p, with: .color(ink), lineWidth: step * 0.4)
                }
            default:
                for r in stride(from: step, through: max(size.width, size.height) * 2, by: step) { context.stroke(Path(ellipseIn: CGRect(x: size.width - r, y: size.height - r, width: 2*r, height: 2*r)), with: .color(ink), lineWidth: step * 0.4) }
            }
        } else if theme.category == 5 {
            for index in 0..<700 {
                let seed = Double(index * 73 + theme.id * 139)
                let x = CGFloat(abs(sin(seed * 12.9898)).truncatingRemainder(dividingBy: 1)) * size.width
                let y = CGFloat(abs(sin(seed * 78.233)).truncatingRemainder(dividingBy: 1)) * size.height
                let r: CGFloat = theme.variant == 4 ? 0.6 : 1.2
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(ink))
            }
            if theme.variant < 2 {
                for index in 0..<14 {
                    var p = Path()
                    for x in stride(from: CGFloat(0), through: size.width, by: 3) {
                        let y = CGFloat(index) * size.height / 12 + sin(x / (theme.variant == 0 ? 25 : 80) + Double(index)) * (theme.variant == 0 ? 15 : 50)
                        if x == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(p, with: .color(ink), lineWidth: CGFloat(index % 3 + 1) * 3)
                }
            }
        }
    }
}
