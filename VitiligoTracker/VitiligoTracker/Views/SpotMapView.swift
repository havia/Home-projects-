import SwiftUI
import SwiftData
import Charts

struct SpotMapView: View {
    let session: Session
    @State private var selectedMeasurement: SpotMeasurement? = nil
    @State private var imageSize: CGSize = .zero

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header info
                sessionHeader

                // Face photo with spot overlays
                spotMapSection

                // Legend
                legendView

                // Spot detail sheet if selected
                if let measurement = selectedMeasurement {
                    spotDetailCard(measurement: measurement)
                }

                // All spots summary list
                spotsSummaryList
            }
            .padding()
        }
        .navigationTitle("Session \(session.formattedDate)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Session Header

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.formattedDate)
                        .font(.headline)
                    Text("\(session.measurements.count) spot(s) detected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if session.uvMinutes > 0 {
                        Label("\(session.uvMinutes, specifier: "%.1f") min UV", systemImage: "sun.max.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !session.medicineDose.isEmpty {
                        Label(session.medicineDose, systemImage: "cross.case.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            if !session.treatmentNotes.isEmpty {
                Text(session.treatmentNotes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Spot Map

    private var spotMapSection: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width

            ZStack {
                // Background photo
                if let photoURL = session.photoURL,
                   let uiImage = UIImage(contentsOfFile: photoURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: availableWidth)
                        .clipped()
                        .onAppear {
                            let ratio = uiImage.size.height / uiImage.size.width
                            imageSize = CGSize(width: availableWidth, height: availableWidth * ratio)
                        }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(width: availableWidth, height: availableWidth)
                        VStack {
                            Image(systemName: "photo.slash")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Photo not available")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onAppear {
                        imageSize = CGSize(width: availableWidth, height: availableWidth)
                    }
                }

                // Spot overlays
                ForEach(session.measurements, id: \.id) { measurement in
                    if let spot = measurement.spot {
                        spotOverlay(
                            measurement: measurement,
                            spot: spot,
                            containerSize: imageSize
                        )
                    }
                }
            }
        }
        .frame(height: imageSize.height > 0 ? imageSize.height : 300)
    }

    private func spotOverlay(
        measurement: SpotMeasurement,
        spot: Spot,
        containerSize: CGSize
    ) -> some View {
        let bounds = measurement.boundingRect
        let x = bounds.origin.x * containerSize.width
        let y = bounds.origin.y * containerSize.height
        let w = max(bounds.width * containerSize.width, 40)
        let h = max(bounds.height * containerSize.height, 40)
        let trend = spot.trend
        let isSelected = selectedMeasurement?.id == measurement.id

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(trendColor(trend), lineWidth: isSelected ? 3 : 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(trendColor(trend).opacity(isSelected ? 0.35 : 0.20))
                )
                .frame(width: w, height: h)

            VStack(spacing: 2) {
                Image(systemName: trend.systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(trendColor(trend))
                Text(spot.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black, radius: 1)
            }
        }
        .position(x: x + w/2, y: y + h/2)
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) {
                selectedMeasurement = (selectedMeasurement?.id == measurement.id) ? nil : measurement
            }
        }
    }

    // MARK: - Legend

    private var legendView: some View {
        HStack(spacing: 20) {
            legendItem(color: .green, label: "Improving")
            legendItem(color: .yellow, label: "Stable")
            legendItem(color: .red, label: "Worsening")
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Spot Detail Card

    private func spotDetailCard(measurement: SpotMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let spot = measurement.spot {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spot.label)
                            .font(.headline)
                        Text("Trend: \(spot.trend.rawValue)")
                            .font(.subheadline)
                            .foregroundStyle(trendColor(spot.trend))
                    }
                }
                Spacer()
                Button {
                    withAnimation { selectedMeasurement = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }

            Divider()

            // Stats
            HStack(spacing: 20) {
                statView(
                    value: String(format: "%.3f%%", measurement.areaNormalizedPx * 100),
                    label: "Relative Area"
                )
                statView(
                    value: String(format: "L*=%.1f", measurement.meanLuminance),
                    label: "Luminance"
                )
            }

            // History chart if multiple measurements
            if let spot = measurement.spot, spot.measurements.count > 1 {
                Divider()
                Text("Area History")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                spotHistoryChart(spot: spot)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    private func statView(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ChartContentBuilder
    private func spotHistoryChartContent(sorted: [SpotMeasurement]) -> some ChartContent {
        ForEach(sorted, id: \.id) { m in
            LineMark(
                x: .value("Date", m.date),
                y: .value("Area", m.areaNormalizedPx * 100)
            )
            .foregroundStyle(Color.blue)
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", m.date),
                y: .value("Area", m.areaNormalizedPx * 100)
            )
            .foregroundStyle(Color.blue)
            .symbolSize(40)
        }
    }

    private func spotHistoryChart(spot: Spot) -> some View {
        let sorted = spot.measurements.sorted { $0.date < $1.date }
        return Chart {
            spotHistoryChartContent(sorted: sorted)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxisLabel("Area %")
        .frame(height: 120)
    }

    // MARK: - Spots Summary List

    private var spotsSummaryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All Detected Spots")
                .font(.headline)

            if session.measurements.isEmpty {
                Text("No spots detected in this session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(session.measurements, id: \.id) { measurement in
                    if let spot = measurement.spot {
                        HStack(spacing: 12) {
                            Image(systemName: spot.trend.systemImage)
                                .foregroundStyle(trendColor(spot.trend))
                                .frame(width: 28, height: 28)
                                .background(trendColor(spot.trend).opacity(0.15))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(spot.label)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(spot.trend.rawValue) · Area: \(measurement.areaNormalizedPx * 100, specifier: "%.2f")%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("L*=\(measurement.meanLuminance, specifier: "%.0f")")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedMeasurement = (selectedMeasurement?.id == measurement.id) ? nil : measurement
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helper

    private func trendColor(_ trend: Trend) -> Color {
        switch trend {
        case .improving: return .green
        case .stable: return .yellow
        case .worsening: return .red
        }
    }
}

#Preview {
    let session = Session(date: Date(), photoPath: "", treatmentNotes: "Test notes", uvMinutes: 2.0, medicineDose: "Tacrolimus")
    return NavigationStack {
        SpotMapView(session: session)
    }
    .modelContainer(for: [Session.self, Spot.self, SpotMeasurement.self], inMemory: true)
}
