import SwiftUI
import SwiftData
import Charts

struct ProgressChartView: View {
    @Query(sort: \Session.date, order: .forward) private var sessions: [Session]
    @Query private var spots: [Spot]

    @State private var selectedSpot: Spot? = nil

    private var improvingCount: Int {
        spots.filter { $0.trend == .improving }.count
    }

    private var stableCount: Int {
        spots.filter { $0.trend == .stable }.count
    }

    private var worseningCount: Int {
        spots.filter { $0.trend == .worsening }.count
    }

    // Total depigmented area per session
    private var totalAreaData: [(date: Date, area: Double)] {
        sessions.map { session in
            let total = session.measurements.reduce(0.0) { $0 + $1.areaNormalizedPx }
            return (date: session.date, area: total * 100)
        }
    }

    // Per-spot data for selected spot
    private var selectedSpotData: [(date: Date, area: Double)] {
        guard let spot = selectedSpot else { return [] }
        return spot.measurements
            .sorted { $0.date < $1.date }
            .map { (date: $0.date, area: $0.areaNormalizedPx * 100) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if sessions.isEmpty {
                        emptyStateView
                    } else {
                        // Summary stats
                        summaryStatsCard

                        // Total area chart
                        totalAreaChartCard

                        // Per-spot chart
                        if !spots.isEmpty {
                            perSpotChartCard
                        }

                        // Spot trend table
                        if !spots.isEmpty {
                            spotTrendTableCard
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 60)
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 72))
                .foregroundStyle(.blue.opacity(0.5))
            VStack(spacing: 8) {
                Text("No Data Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Record sessions in the Capture tab to see your progress charts here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Summary Stats

    private var summaryStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

            HStack(spacing: 12) {
                statBadge(
                    count: improvingCount,
                    label: "Improving",
                    color: .green,
                    icon: "arrow.down.circle.fill"
                )
                statBadge(
                    count: stableCount,
                    label: "Stable",
                    color: .yellow,
                    icon: "minus.circle.fill"
                )
                statBadge(
                    count: worseningCount,
                    label: "Worsening",
                    color: .red,
                    icon: "arrow.up.circle.fill"
                )
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sessions.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(spots.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Tracked Spots")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statBadge(count: Int, label: String, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Total Area Chart

    private var totalAreaChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Total Depigmented Area Over Time")
                .font(.headline)
            Text("Sum of all spot areas per session")
                .font(.caption)
                .foregroundStyle(.secondary)

            if totalAreaData.count < 2 {
                Text("Add more sessions to see the trend line.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                Chart {
                    ForEach(Array(totalAreaData.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Area %", point.area)
                        )
                        .foregroundStyle(totalAreaGradient)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Area %", point.area)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Area %", point.area)
                        )
                        .foregroundStyle(Color.blue)
                        .symbolSize(50)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                        AxisGridLine()
                    }
                }
                .chartYAxisLabel("Area %")
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(v, specifier: "%.2f")%")
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var totalAreaGradient: LinearGradient {
        let first = totalAreaData.first?.area ?? 0
        let last = totalAreaData.last?.area ?? 0
        let improving = last < first
        return LinearGradient(
            colors: improving ? [.green, .green] : [.red, .orange],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Per-Spot Chart

    private var perSpotChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spot History")
                .font(.headline)

            Picker("Select Spot", selection: $selectedSpot) {
                Text("Select a spot...").tag(Optional<Spot>.none)
                ForEach(spots) { spot in
                    Text(spot.label).tag(Optional(spot))
                }
            }
            .pickerStyle(.menu)
            .padding(8)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let spot = selectedSpot {
                if selectedSpotData.count < 2 {
                    Text("Need at least 2 sessions with this spot to show a chart.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    let trendColor = spotTrendColor(spot)
                    Chart {
                        ForEach(Array(selectedSpotData.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Area %", point.area)
                            )
                            .foregroundStyle(trendColor)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Area %", point.area)
                            )
                            .foregroundStyle(trendColor)
                            .symbolSize(60)
                            .annotation(position: .top, alignment: .center) {
                                Text("\(point.area, specifier: "%.2f")%")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisValueLabel(format: .dateTime.month().day())
                            AxisGridLine()
                        }
                    }
                    .chartYAxisLabel("Area %")
                    .frame(height: 180)
                }

                // Also show luminance history
                let lumData = spot.measurements
                    .sorted { $0.date < $1.date }
                    .map { (date: $0.date, lum: $0.meanLuminance) }

                if lumData.count >= 2 {
                    Divider()
                    Text("Skin Luminance (L*) History")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Higher L* = more depigmented · Lower L* = repigmentation (improving)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Chart {
                        ForEach(Array(lumData.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("L*", point.lum)
                            )
                            .foregroundStyle(Color.purple)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("L*", point.lum)
                            )
                            .foregroundStyle(Color.purple)
                            .symbolSize(50)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartYAxisLabel("L* value")
                    .frame(height: 140)
                }
            } else {
                Text("Select a spot above to see its individual history.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Spot Trend Table

    private var spotTrendTableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All Spots Summary")
                .font(.headline)

            ForEach(spots) { spot in
                let color = spotTrendColor(spot)
                HStack(spacing: 12) {
                    Image(systemName: spot.trend.systemImage)
                        .foregroundStyle(color)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(spot.label)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(spot.measurements.count) measurement(s) · \(spot.trend.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let latest = spot.latestMeasurement {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(latest.areaNormalizedPx * 100, specifier: "%.3f")%")
                                .font(.caption)
                                .monospacedDigit()
                            Text("L*=\(latest.meanLuminance, specifier: "%.0f")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func spotTrendColor(_ spot: Spot) -> Color {
        switch spot.trend {
        case .improving: return .green
        case .stable: return .yellow
        case .worsening: return .red
        }
    }
}

#Preview {
    ProgressChartView()
        .modelContainer(for: [Session.self, Spot.self, SpotMeasurement.self], inMemory: true)
}
