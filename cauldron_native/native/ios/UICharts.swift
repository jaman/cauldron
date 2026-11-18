import Charts
import MapKit
import SwiftUI

struct ChartPoint: Identifiable {
    let id: Int
    let series: String
    let category: String
    let number: Double
    let date: Date
    let y: Double
}

struct ChartSeries {
    let name: String
    let mark: String
    let colour: Color?
    let points: [ChartPoint]
}

struct NodeChart: View {
    let node: UINode

    var body: some View {
        content
            .chartLegend(node.bool("legend") ? .visible : .hidden)
            .frame(height: hasFrameHeight(node) ? nil : 240)
    }

    @ViewBuilder private var content: some View {
        if series.first?.mark == "sector" {
            Chart(series.first?.points ?? []) { point in
                SectorMark(angle: .value(yLabel, point.y), innerRadius: .ratio(node.bool("donut") ? 0.6 : 0), angularInset: 1)
                    .foregroundStyle(by: .value(xLabel, point.category))
            }
        } else {
            Chart {
                ForEach(series, id: \.name) { one in
                    ForEach(one.points) { point in marks(one, point) }
                }
            }
            .chartXAxisLabel(xLabel)
            .chartYAxisLabel(yLabel)
            .chartYScale(domain: yDomain)
            .chartForegroundStyleScale(domain: series.map(\.name), range: colours)
        }
    }

    @ChartContentBuilder private func marks(_ one: ChartSeries, _ point: ChartPoint) -> some ChartContent {
        switch node.string("x_type") {
        case "date": mark(one.mark, x: PlottableValue.value(xLabel, point.date), point: point)
        case "number": mark(one.mark, x: PlottableValue.value(xLabel, point.number), point: point)
        default: mark(one.mark, x: PlottableValue.value(xLabel, point.category), point: point)
        }
    }

    @ChartContentBuilder private func mark<X: Plottable>(_ kind: String, x: PlottableValue<X>, point: ChartPoint) -> some ChartContent {
        let y = PlottableValue.value(yLabel, point.y)
        let series = PlottableValue.value("Series", point.series)
        switch kind {
        case "line": LineMark(x: x, y: y, series: series).foregroundStyle(by: series)
        case "area": AreaMark(x: x, y: y, series: series).foregroundStyle(by: series)
        case "point": PointMark(x: x, y: y).foregroundStyle(by: series)
        default: BarMark(x: x, y: y).foregroundStyle(by: series).position(by: series)
        }
    }

    private var xLabel: String { node.string("x_label") ?? "" }
    private var yLabel: String { node.string("y_label") ?? "" }

    private var yDomain: ClosedRange<Double> {
        if let range = node.props["y_range"] as? [NSNumber], range.count == 2 {
            return range[0].doubleValue...range[1].doubleValue
        }
        let values = series.flatMap { $0.points.map(\.y) }
        return min(0, values.min() ?? 0)...max(values.max() ?? 1, 1)
    }

    private var colours: [Color] {
        let defaults: [Color] = [.accentColor, .orange, .green, .purple, .pink, .teal, .yellow, .red]
        return series.enumerated().map { index, one in one.colour ?? defaults[index % defaults.count] }
    }

    private var series: [ChartSeries] {
        var counter = 0
        return (node.props["series"] as? [[String: Any]] ?? []).map { raw in
            let name = raw["name"] as? String ?? ""
            let points: [ChartPoint] = (raw["points"] as? [[Any]] ?? []).compactMap { pair in
                guard pair.count == 2, let y = (pair[1] as? NSNumber)?.doubleValue else { return nil }
                counter += 1
                let number = (pair[0] as? NSNumber)?.doubleValue ?? 0
                return ChartPoint(
                    id: counter,
                    series: name,
                    category: (pair[0] as? String) ?? "\(pair[0])",
                    number: number,
                    date: Date(timeIntervalSince1970: number / 1000),
                    y: y
                )
            }
            return ChartSeries(name: name, mark: raw["mark"] as? String ?? "bar", colour: hexColour(raw["colour"]), points: points)
        }
    }
}

func hasFrameHeight(_ node: UINode) -> Bool {
    node.modifiers.contains { ($0.first as? String) == "frame" && (($0.last as? [String: Any])?["height"] != nil) }
}

struct MapPin: Identifiable {
    let id: Int
    let title: String
    let coordinate: CLLocationCoordinate2D
    let colour: Color?
}

struct UserMoves: ViewModifier {
    @Binding var touched: Bool

    #if os(tvOS)
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onMapCameraChange(frequency: .continuous) { if focused { touched = true } }
    }
    #else
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in touched = true })
            .simultaneousGesture(MagnifyGesture().onChanged { _ in touched = true })
    }
    #endif
}

final class NodeMapCamera: ObservableObject {
    @Published var position: MapCameraPosition = .automatic
    var placed: String?
}

struct NodeMap: View {
    let node: UINode
    @StateObject private var camera = NodeMapCamera()
    @State private var selection: Int?
    @State private var touched = false

    var body: some View {
        Map(position: $camera.position, selection: $selection) {
            ForEach(pins) { pin in
                Marker(pin.title, coordinate: pin.coordinate)
                    .tint(pin.colour ?? .red)
                    .tag(pin.id)
            }
            if node.bool("user_location") { UserAnnotation() }
        }
        .mapStyle(style)
        .mapControls {
            if node.bool("user_location") { MapUserLocationButton() }
            MapCompass()
        }
        .frame(height: hasFrameHeight(node) ? nil : 300)
        .modifier(UserMoves(touched: $touched))
        .onAppear(perform: place)
        .onChange(of: placement) { place() }
        .onChange(of: selection) {
            guard let selection else { return }
            UIEvents(id: node.id).send("select", selection)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            guard touched, node.events.contains("move") else { return }
            touched = false
            let region = context.region
            let metres = region.span.latitudeDelta * 111_000
            UIEvents(id: node.id).send("move", [
                "latitude": region.center.latitude,
                "longitude": region.center.longitude,
                "distance": metres
            ])
        }
    }

    private var placement: String {
        "\(node.props["center"] ?? "")-\(node.double("distance") ?? 1000)"
    }

    private func place() {
        guard camera.placed != placement else { return }
        camera.placed = placement
        guard let center = node.props["center"] as? [NSNumber], center.count == 2 else { return }
        let coordinate = CLLocationCoordinate2D(latitude: center[0].doubleValue, longitude: center[1].doubleValue)
        let distance = node.double("distance") ?? 1000
        camera.position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: distance, longitudinalMeters: distance))
    }

    private var style: MapStyle {
        switch node.string("style") {
        case "satellite": .imagery
        case "hybrid": .hybrid
        default: .standard
        }
    }

    private var pins: [MapPin] {
        (node.props["markers"] as? [[String: Any]] ?? []).enumerated().compactMap { index, raw in
            guard let latitude = (raw["latitude"] as? NSNumber)?.doubleValue,
                  let longitude = (raw["longitude"] as? NSNumber)?.doubleValue else { return nil }
            return MapPin(
                id: index,
                title: raw["title"] as? String ?? "",
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                colour: hexColour(raw["colour"])
            )
        }
    }
}
