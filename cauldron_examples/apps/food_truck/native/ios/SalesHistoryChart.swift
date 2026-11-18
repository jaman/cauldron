import Charts
import SwiftUI

struct CitySales: Identifiable {
    var id: String { city }
    let city: String
    let entries: [SalesEntry]
}

struct SalesEntry: Identifiable {
    var id: Date { date }
    let date: Date
    let sales: Int
}

struct SalesHistoryChartView: CauldronNativeView {
    static let name = "sales_history_chart"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        let cities = (node.props["cities"] as? [[String: Any]] ?? []).map { city in
            CitySales(
                city: city["name"] as? String ?? "",
                entries: (city["entries"] as? [[Any]] ?? []).compactMap { pair in
                    guard pair.count == 2, let time = (pair[0] as? NSNumber)?.doubleValue,
                          let sales = (pair[1] as? NSNumber)?.intValue else { return nil }
                    return SalesEntry(date: Date(timeIntervalSince1970: time), sales: sales)
                }
            )
        }
        let locked = node.bool("locked")
        Chart {
            ForEach(cities) { city in
                ForEach(city.entries) { entry in
                    LineMark(x: .value("Day", entry.date), y: .value("Sales", entry.sales))
                        .foregroundStyle(by: .value("Location", city.city))
                        .interpolationMethod(.cardinal)
                        .symbol(by: .value("Location", city.city))
                        .opacity(locked ? 0 : 1)
                }
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartLegend(position: .top)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(roundLowerBound: false, roundUpperBound: false)) { value in
                if value.index < value.count - 1 { AxisValueLabel() }
                AxisTick()
                AxisGridLine()
            }
        }
        .chartPlotStyle { plot in
            plot.chartOverlay { _ in
                if locked {
                    HStack {
                        Image(systemName: "lock")
                        Text("Premium Feature")
                    }
                    .foregroundStyle(.secondary)
                    .padding(20)
                    .background(.background.shadow(.drop(color: .black.opacity(0.15), radius: 6, y: 2)), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
                }
            }
        }
        .frame(minHeight: 300)
    }
}
