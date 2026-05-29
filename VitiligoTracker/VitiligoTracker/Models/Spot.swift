import Foundation
import SwiftData

enum Trend: String, Codable {
    case improving = "Improving"
    case stable = "Stable"
    case worsening = "Worsening"

    var color: String {
        switch self {
        case .improving: return "green"
        case .stable: return "yellow"
        case .worsening: return "red"
        }
    }

    var systemImage: String {
        switch self {
        case .improving: return "arrow.down.circle.fill"
        case .stable: return "minus.circle.fill"
        case .worsening: return "arrow.up.circle.fill"
        }
    }
}

@Model
final class Spot {
    var id: UUID
    var label: String
    var normalizedX: Double
    var normalizedY: Double
    var firstSeenDate: Date

    @Relationship(deleteRule: .cascade, inverse: \SpotMeasurement.spot)
    var measurements: [SpotMeasurement]

    init(
        id: UUID = UUID(),
        label: String = "",
        normalizedX: Double = 0,
        normalizedY: Double = 0,
        firstSeenDate: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.firstSeenDate = firstSeenDate
        self.measurements = []
    }

    var trend: Trend {
        let sorted = measurements.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return .stable }

        let last = sorted[sorted.count - 1]
        let prev = sorted[sorted.count - 2]

        let areaChange = last.areaNormalizedPx - prev.areaNormalizedPx
        let luminanceChange = last.meanLuminance - prev.meanLuminance

        // Area shrinking OR luminance decreasing toward normal = improving
        // Use a 5% threshold to avoid noise
        let areaThreshold = prev.areaNormalizedPx * 0.05
        let luminanceThreshold = 2.0 // LAB L* units

        if areaChange < -areaThreshold || luminanceChange < -luminanceThreshold {
            return .improving
        } else if areaChange > areaThreshold || luminanceChange > luminanceThreshold {
            return .worsening
        } else {
            return .stable
        }
    }

    var latestMeasurement: SpotMeasurement? {
        measurements.sorted { $0.date < $1.date }.last
    }

    var normalizedCenter: CGPoint {
        CGPoint(x: normalizedX, y: normalizedY)
    }
}
