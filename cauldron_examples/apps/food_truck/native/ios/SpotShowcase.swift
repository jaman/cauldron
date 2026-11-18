import MapKit
import SwiftUI

struct SpotShowcaseView: CauldronNativeView {
    static let name = "spot_showcase"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        let place = CLLocationCoordinate2D(latitude: node.double("latitude") ?? 0, longitude: node.double("longitude") ?? 0)
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let seconds = timeline.date.timeIntervalSince1970
                let heading = seconds.truncatingRemainder(dividingBy: 240) / 240
                let swing = seconds.truncatingRemainder(dividingBy: 60) / 60
                let pitch = 50 + 10 * eased(swing <= 0.5 ? swing * 2 : 2 - swing * 2)
                let wide = min(max((proxy.size.width - 350) / (1000 - proxy.size.width), 0), 1)
                ShowcaseMap(
                    place: place,
                    distance: ((1 - wide) * 0.5 + 1) * (node.double("distance") ?? 1000),
                    pitch: pitch,
                    heading: 360 * heading
                )
            }
        }
        #if os(iOS)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.15), location: 0.1),
                    .init(color: .black, location: 0.6),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        #endif
        .accessibilityHidden(true)
    }

    private func eased(_ value: Double) -> Double {
        let time = min(max(value, 0), 1)
        return time * time * (3 - 2 * time)
    }
}

#if os(macOS)
typealias ShowcaseRepresentable = NSViewRepresentable
#else
typealias ShowcaseRepresentable = UIViewRepresentable
#endif

struct ShowcaseMap: ShowcaseRepresentable {
    let place: CLLocationCoordinate2D
    let distance: Double
    let pitch: Double
    let heading: Double

    #if os(macOS)
    func makeNSView(context: Context) -> MKMapView { made() }
    func updateNSView(_ map: MKMapView, context: Context) { aim(map) }
    #else
    func makeUIView(context: Context) -> MKMapView { made() }
    func updateUIView(_ map: MKMapView, context: Context) { aim(map) }
    #endif

    private func made() -> MKMapView {
        let map = MKMapView()
        let configuration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        map.preferredConfiguration = configuration
        map.isZoomEnabled = false
        map.isScrollEnabled = false
        #if !os(tvOS)
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.showsCompass = false
        #endif
        return map
    }

    private func aim(_ map: MKMapView) {
        map.camera = MKMapCamera(lookingAtCenter: place, fromDistance: distance, pitch: pitch, heading: heading)
    }
}
