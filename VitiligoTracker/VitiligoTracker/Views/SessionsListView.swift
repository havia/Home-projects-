import SwiftUI
import SwiftData

struct SessionsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]

    @State private var selectedSession: Session? = nil
    @State private var showDeleteConfirm = false
    @State private var sessionToDelete: Session? = nil

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyStateView
                } else {
                    sessionsList
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !sessions.isEmpty {
                        Text("\(sessions.count) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("Delete Session", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let session = sessionToDelete {
                        deleteSession(session)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the session and all its spot measurements.")
            }
        }
    }

    // MARK: - Sessions List

    private var sessionsList: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink {
                    SpotMapView(session: session)
                } label: {
                    SessionRowView(session: session)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        sessionToDelete = session
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 72))
                .foregroundStyle(.blue.opacity(0.6))

            VStack(spacing: 8) {
                Text("No Sessions Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Take a photo or import from your library to start tracking your vitiligo progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    // MARK: - Delete

    private func deleteSession(_ session: Session) {
        // Delete photo file if it exists
        if let url = session.photoURL {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(session)
        try? modelContext.save()
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(session.formattedDate)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                // Spot count with trend breakdown
                HStack(spacing: 8) {
                    let improving = session.measurements.filter { $0.spot?.trend == .improving }.count
                    let worsening = session.measurements.filter { $0.spot?.trend == .worsening }.count
                    let stable = session.measurements.filter { $0.spot?.trend == .stable }.count

                    if session.measurements.isEmpty {
                        Text("No spots detected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        if improving > 0 {
                            trendBadge(count: improving, color: .green, icon: "arrow.down")
                        }
                        if stable > 0 {
                            trendBadge(count: stable, color: .yellow, icon: "minus")
                        }
                        if worsening > 0 {
                            trendBadge(count: worsening, color: .red, icon: "arrow.up")
                        }
                    }
                }

                // Treatment info
                HStack(spacing: 8) {
                    if session.uvMinutes > 0 {
                        Label("\(session.uvMinutes, specifier: "%.1f")m UV", systemImage: "sun.max.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if !session.medicineDose.isEmpty {
                        Label(session.medicineDose, systemImage: "cross.case.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var thumbnailView: some View {
        Group {
            if let photoURL = session.photoURL,
               let uiImage = UIImage(contentsOfFile: photoURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "photo.slash")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }
        }
    }

    private func trendBadge(count: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.bold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}

#Preview {
    SessionsListView()
        .modelContainer(for: [Session.self, Spot.self, SpotMeasurement.self], inMemory: true)
}
