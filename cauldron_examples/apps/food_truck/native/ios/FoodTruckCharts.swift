import Charts
import SwiftUI

struct ForecastEntry: Identifiable {
    var id: Date { date }
    let date: Date
    let degrees: Double
    let daylight: Bool
}

struct ForecastChartView: CauldronNativeView {
    static let name = "forecast_chart"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        let entries = (node.props["entries"] as? [[String: Any]] ?? []).compactMap { entry -> ForecastEntry? in
            guard let time = (entry["time"] as? NSNumber)?.doubleValue,
                  let degrees = (entry["degrees"] as? NSNumber)?.doubleValue else { return nil }
            return ForecastEntry(date: Date(timeIntervalSince1970: time), degrees: degrees, daylight: entry["daylight"] as? Bool ?? true)
        }
        if entries.count > 1 {
            ForecastChart(entries: entries, unit: node.string("unit") ?? "°")
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 180)
        }
    }
}

struct ForecastChart: View {
    let entries: [ForecastEntry]
    let unit: String

    private var low: Double { (entries.map(\.degrees).min() ?? 0) - 2 }

    private var nights: [Range<Date>] {
        var start: Date?
        var ranges: [Range<Date>] = []
        for entry in entries {
            if entry.daylight, let from = start {
                ranges.append(from..<entry.date)
                start = nil
            } else if !entry.daylight && start == nil {
                start = entry.date
            }
        }
        if let from = start, let last = entries.last { ranges.append(from..<last.date) }
        return ranges
    }

    private var bins: ClosedRange<Date> {
        let calendar = Calendar.current
        let every3 = entries.map(\.date).filter { calendar.component(.hour, from: $0).isMultiple(of: 3) }
        return (every3.first ?? entries[0].date)...(every3.last ?? entries[entries.count - 1].date)
    }

    private func degrees(at date: Date) -> Double {
        entries.first { $0.date == date }?.degrees ?? low
    }

    var body: some View {
        Chart {
            area("Temperature", 0)
                .foregroundStyle(.linearGradient(colors: [.teal, .yellow], startPoint: .bottom, endPoint: .top))
            ForEach(nights, id: \.lowerBound) { night in
                RectangleMark(xStart: .value("Hour", night.lowerBound), xEnd: .value("Hour", night.upperBound))
                    .opacity(0.5)
                    .mask { area("Mask", night.lowerBound.timeIntervalSince1970) }
                if night.lowerBound != entries.first?.date {
                    edge(night.lowerBound, symbol: "moon.circle.fill", shadow: 1)
                }
                if night.upperBound != entries.last?.date {
                    edge(night.upperBound, symbol: "sun.max.circle.fill", shadow: -1)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: DateBins(unit: .hour, by: 3, range: bins).thresholds) { _ in
                AxisValueLabel(format: .dateTime.hour())
                AxisTick()
                AxisGridLine()
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(values: .automatic(minimumStride: 5, desiredCount: 6, roundLowerBound: false)) { value in
                AxisValueLabel("\((value.as(Double.self) ?? 0).formatted())\(unit)")
                AxisTick()
                AxisGridLine()
            }
        }
        .frame(minHeight: 180)
    }

    @ChartContentBuilder private func area(_ series: String, _ value: Double) -> some ChartContent {
        ForEach(entries) { entry in
            AreaMark(
                x: .value("Hour", entry.date),
                yStart: .value("Temperature", low),
                yEnd: .value("Temperature", entry.degrees),
                series: .value(series, value)
            )
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder private func edge(_ date: Date, symbol: String, shadow: CGFloat) -> some ChartContent {
        RectangleMark(
            x: .value("Date", date),
            yStart: .value("Temperature", low - 0.5),
            yEnd: .value("Temperature", degrees(at: date) + 0.5),
            width: .fixed(4)
        )
        .foregroundStyle(.indigo.shadow(.drop(color: .white.opacity(0.25), radius: 0, x: shadow)))
        .cornerRadius(2)
        .annotation(position: .top, alignment: .bottom, spacing: 5) {
            Image(systemName: symbol)
                .imageScale(.large)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .indigo)
        }
    }
}

struct TopSale: Identifiable {
    var id: String { name }
    let name: String
    let layers: [String]
    let sales: Int
}

struct TopSalesChartView: CauldronNativeView {
    static let name = "top_sales_chart"
    let node: UINode
    let events: UIEvents

    init(node: UINode, events: UIEvents) {
        self.node = node
        self.events = events
    }

    var body: some View {
        let sales = (node.props["sales"] as? [[String: Any]] ?? []).map { sale in
            TopSale(
                name: sale["name"] as? String ?? "",
                layers: sale["layers"] as? [String] ?? [],
                sales: (sale["sales"] as? NSNumber)?.intValue ?? 0
            )
        }
        TopSalesChart(sales: sales)
    }
}

struct TopSalesChart: View {
    let sales: [TopSale]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Total Sales")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(sales.map(\.sales).reduce(0, +).formatted()) Donuts")
                .font(.headline)
            Chart {
                ForEach(sales.sorted { $0.sales == $1.sales ? $0.name < $1.name : $0.sales < $1.sales }) { sale in
                    BarMark(x: .value("Donut", sale.name), y: .value("Sales", sale.sales))
                        .cornerRadius(6, style: .continuous)
                        .foregroundStyle(.linearGradient(colors: [Color("BarBottomColor"), .accentColor], startPoint: .bottom, endPoint: .top))
                        .annotation(position: .top, alignment: .top) {
                            Text(sale.sales.formatted())
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(.quaternary.opacity(0.5), in: Capsule())
                                .background(in: Capsule())
                                .font(.caption)
                        }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: IntegerFormatStyle<Int>())
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        let sale = sales.first { $0.name == value.as(String.self) }
                        VStack {
                            DonutLayers(layers: sale?.layers ?? []).frame(height: 35)
                            Text(sale?.name ?? "")
                                .lineLimit(2, reservesSpace: true)
                                .multilineTextAlignment(.center)
                        }
                        .frame(idealWidth: 80)
                        .padding(.horizontal, 4)
                    }
                }
            }
            .frame(height: 300)
            .padding(.top, 20)
        }
    }
}
