import SwiftUI

struct MeterView: CauldronNativeView {
    static let name = "meter"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    #if os(tvOS)
    var body: some View {
        let value = node.double("value") ?? 0
        ZStack {
            Circle().stroke(Color.primary.opacity(0.15), lineWidth: 8)
            Circle()
                .trim(from: 0, to: value)
                .stroke(AngularGradient(colors: [.green, .yellow, .red], center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(value * 100))")
        }
        .frame(width: 80, height: 80)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    #else
    var body: some View {
        let value = node.double("value") ?? 0
        Gauge(value: value) {
            Text("Level")
        } currentValueLabel: {
            Text("\(Int(value * 100))")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(Gradient(colors: [.green, .yellow, .red]))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    #endif
}
