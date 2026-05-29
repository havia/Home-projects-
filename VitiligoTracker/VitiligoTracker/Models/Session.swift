import Foundation
import SwiftData

@Model
final class Session {
    var id: UUID
    var date: Date
    var photoPath: String
    var treatmentNotes: String
    var uvMinutes: Double
    var medicineDose: String

    @Relationship(deleteRule: .cascade, inverse: \SpotMeasurement.session)
    var measurements: [SpotMeasurement]

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        photoPath: String = "",
        treatmentNotes: String = "",
        uvMinutes: Double = 0,
        medicineDose: String = ""
    ) {
        self.id = id
        self.date = date
        self.photoPath = photoPath
        self.treatmentNotes = treatmentNotes
        self.uvMinutes = uvMinutes
        self.medicineDose = medicineDose
        self.measurements = []
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var spotCount: Int {
        measurements.count
    }

    var photoURL: URL? {
        guard !photoPath.isEmpty else { return nil }
        return URL(fileURLWithPath: photoPath)
    }
}
