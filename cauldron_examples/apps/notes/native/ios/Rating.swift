import SwiftUI

struct RatingView: CauldronNativeView {
    static let name = "rating"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        let value = Int(node.double("value") ?? 0)
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    events.send("change", star == value ? 0 : star)
                } label: {
                    Image(systemName: star <= value ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(star <= value ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
