import SwiftUI

struct BrandHeaderView: CauldronNativeView {
    static let name = "brand_header"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        BrandHeader(animated: !node.bool("still"), scale: node.bool("reduced") ? 0.5 : 1)
    }
}

struct BrandHeader: View {
    let animated: Bool
    let scale: Double

    private var sky: Gradient {
        Gradient(colors: [Color("header/Sky Start"), Color("header/Sky End")])
    }

    var body: some View {
        TimelineView(.animation(paused: !animated)) { timeline in
            let scene = HeaderScene(time: timeline.date.timeIntervalSince1970)
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let centerX = size.width * 0.5
                context.fill(
                    Rectangle().path(in: rect),
                    with: .radialGradient(sky, center: CGPoint(x: rect.midX, y: 400 * scale), startRadius: 0, endRadius: 600)
                )
                for layer in scene.background {
                    draw(layer, in: &context, x: centerX, y: (750 + layer.offset) * scale)
                }
                context.drawLayer { context in
                    context.translateBy(x: centerX, y: 350 * scale)
                    context.scaleBy(x: scale, y: scale)
                    context.draw(Image("header/layer/8 Road"), at: .zero)
                }
                context.drawLayer { context in
                    context.translateBy(x: centerX, y: 307 * scale)
                    context.scaleBy(x: scale, y: scale)
                    context.draw(scene.truck, at: .zero)
                }
                for layer in scene.foreground {
                    draw(layer, in: &context, x: centerX, y: 770 * scale)
                }
            }
            .padding(.top, -200 * scale)
        }
        .frame(height: 200 * scale)
        .accessibilityHidden(true)
    }

    private func draw(_ layer: TurningLayer, in context: inout GraphicsContext, x: CGFloat, y: CGFloat) {
        context.drawLayer { context in
            context.translateBy(x: x, y: y)
            context.rotate(by: -layer.turn)
            context.scaleBy(x: scale, y: scale)
            context.draw(layer.image, at: .zero)
        }
    }
}

struct TurningLayer {
    let image: Image
    let turn: Angle
    var offset: Double = 0
}

struct HeaderScene {
    let background: [TurningLayer]
    let foreground: [TurningLayer]
    let truck: Image

    init(time: TimeInterval) {
        func layer(_ name: String, _ period: Double, _ offset: Double = 0) -> TurningLayer {
            let turn = Angle.radians(time.truncatingRemainder(dividingBy: period) / period * .pi * 2)
            return TurningLayer(image: Image("header/layer/\(name)"), turn: turn, offset: offset)
        }
        background = [
            layer("1 Small Clouds", 760),
            layer("2 Medium Clouds", 720, -15),
            layer("3 Mountains", 840, -10),
            layer("4 Big Clouds", 400),
            layer("5 Ocean", 480),
            layer("6 Balloons", 540),
            layer("7 Trees", 180, -10)
        ]
        foreground = [layer("9 Foreground", 96)]
        let frames = 4.0
        let cycle = frames / 12
        let frame = Int(floor(time.truncatingRemainder(dividingBy: cycle) / cycle * frames))
        truck = Image("header/truck/Frame \(frame + 1)")
    }
}
