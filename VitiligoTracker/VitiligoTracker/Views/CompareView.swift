import SwiftUI
import SwiftData

struct CompareView: View {
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]

    @State private var sessionA: Session? = nil
    @State private var sessionB: Session? = nil
    @State private var showDeltas = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if sessions.count < 2 {
                        notEnoughSessionsView
                    } else {
                        sessionPickersSection

                        if sessionA != nil || sessionB != nil {
                            comparisonSection
                        }

                        if showDeltas, let a = sessionA, let b = sessionB {
                            deltaSection(sessionA: a, sessionB: b)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if sessions.count >= 2 && sessionA == nil {
                    sessionA = sessions.last   // oldest
                    sessionB = sessions.first  // newest
                }
            }
        }
    }

    // MARK: - Not Enough Sessions

    private var notEnoughSessionsView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 60)
            Image(systemName: "rectangle.split.2x1.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue.opacity(0.5))
            VStack(spacing: 8) {
                Text("Need 2+ Sessions")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Record at least two sessions to compare them side by side.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Session Pickers

    private var sessionPickersSection: some View {
        HStack(spacing: 12) {
            sessionPicker(label: "Session A", selection: $sessionA)
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.secondary)
            sessionPicker(label: "Session B", selection: $sessionB)
        }
    }

    private func sessionPicker(label: String, selection: Binding<Session?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.semibold)

            Menu {
                ForEach(sessions) { session in
                    Button(session.formattedDate) {
                        selection.wrappedValue = session
                    }
                }
            } label: {
                HStack {
                    Text(selection.wrappedValue?.formattedDate ?? "Choose...")
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(selection.wrappedValue != nil ? .primary : .secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Side-by-Side Comparison

    private var comparisonSection: some View {
        VStack(spacing: 8) {
            Text("Side-by-Side")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 12) {
                sessionPhotoCard(session: sessionA, label: "A")
                sessionPhotoCard(session: sessionB, label: "B")
            }
        }
    }

    private func sessionPhotoCard(session: Session?, label: String) -> some View {
        VStack(spacing: 6) {
            // Date label
            Text(session?.formattedDate ?? "Not selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32)

            // Photo with overlays
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    if let s = session, let url = s.photoURL,
                       let uiImage = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: size.width)
                            .clipped()

                        // Spot overlays
                        ForEach(s.measurements, id: \.id) { measurement in
                            if let spot = measurement.spot {
                                compactSpotOverlay(
                                    measurement: measurement,
                                    spot: spot,
                                    containerSize: size
                                )
                            }
                        }
                    } else if session != nil {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray5))
                            Image(systemName: "photo.slash")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                            VStack(spacing: 4) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                                    .font(.title2)
                                Text("Not selected")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )

            // Stats
            if let s = session {
                VStack(spacing: 2) {
                    Text("\(s.measurements.count) spots")
                        .font(.caption)
                        .fontWeight(.medium)
                    let total = s.measurements.reduce(0.0) { $0 + $1.areaNormalizedPx } * 100
                    Text("Total area: \(total, specifier: "%.3f")%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func compactSpotOverlay(
        measurement: SpotMeasurement,
        spot: Spot,
        containerSize: CGSize
    ) -> some View {
        let bounds = measurement.boundingRect
        let x = bounds.origin.x * containerSize.width
        let y = bounds.origin.y * containerSize.height
        let w = max(bounds.width * containerSize.width, 24)
        let h = max(bounds.height * containerSize.height, 24)
        let color = trendColor(spot.trend)

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(color, lineWidth: 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.25))
                )
                .frame(width: w, height: h)

            Image(systemName: spot.trend.systemImage)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
        }
        .position(x: x + w/2, y: y + h/2)
    }

    // MARK: - Delta Section

    private func deltaSection(sessionA: Session, sessionB: Session) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Changes: A → B")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation { showDeltas.toggle() }
                } label: {
                    Image(systemName: showDeltas ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }

            // Overall area delta
            let totalA = sessionA.measurements.reduce(0.0) { $0 + $1.areaNormalizedPx } * 100
            let totalB = sessionB.measurements.reduce(0.0) { $0 + $1.areaNormalizedPx } * 100
            let totalDelta = totalB - totalA

            HStack {
                Label("Total Area Change", systemImage: "sum")
                    .font(.subheadline)
                Spacer()
                Text(totalDelta >= 0 ? "+\(totalDelta, specifier: "%.3f")%" : "\(totalDelta, specifier: "%.3f")%")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(totalDelta < 0 ? .green : (totalDelta > 0 ? .red : .secondary))
                    .monospacedDigit()
            }
            .padding(10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Divider()

            // Per-spot deltas — match by spot label
            let spotsInA = Dictionary(uniqueKeysWithValues: sessionA.measurements.compactMap { m -> (String, SpotMeasurement)? in
                guard let spot = m.spot else { return nil }
                return (spot.label, m)
            })
            let spotsInB = Dictionary(uniqueKeysWithValues: sessionB.measurements.compactMap { m -> (String, SpotMeasurement)? in
                guard let spot = m.spot else { return nil }
                return (spot.label, m)
            })

            let allLabels = Set(spotsInA.keys).union(spotsInB.keys).sorted()

            if allLabels.isEmpty {
                Text("No matching spots between sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(allLabels, id: \.self) { label in
                    spotDeltaRow(
                        label: label,
                        measurementA: spotsInA[label],
                        measurementB: spotsInB[label]
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func spotDeltaRow(
        label: String,
        measurementA: SpotMeasurement?,
        measurementB: SpotMeasurement?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                // Area delta
                if let a = measurementA, let b = measurementB {
                    let areaDelta = (b.areaNormalizedPx - a.areaNormalizedPx) * 100
                    let areaPercent = a.areaNormalizedPx > 0
                        ? ((b.areaNormalizedPx - a.areaNormalizedPx) / a.areaNormalizedPx) * 100
                        : 0

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Area")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(areaPercent >= 0 ? "+\(areaPercent, specifier: "%.1f")%" : "\(areaPercent, specifier: "%.1f")%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(areaDelta < 0 ? .green : (areaDelta > 0 ? .red : .secondary))
                            .monospacedDigit()
                    }

                    // Luminance delta
                    let lumDelta = b.meanLuminance - a.meanLuminance
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Luminance")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(lumDelta >= 0 ? "+\(lumDelta, specifier: "%.1f") L*" : "\(lumDelta, specifier: "%.1f") L*")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(lumDelta < 0 ? .green : (lumDelta > 0 ? .red : .secondary))
                            .monospacedDigit()
                    }
                } else if measurementA == nil {
                    Text("New spot in B")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Resolved in B")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Spacer()
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
    CompareView()
        .modelContainer(for: [Session.self, Spot.self, SpotMeasurement.self], inMemory: true)
}
