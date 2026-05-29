import Foundation
import SwiftData
import CoreGraphics

@Model
final class SpotMeasurement {
    var id: UUID
    var session: Session?
    var spot: Spot?
    var areaNormalizedPx: Double
    var meanLuminance: Double
    var date: Date

    // Store CGRect as four doubles
    var rectX: Double
    var rectY: Double
    var rectWidth: Double
    var rectHeight: Double

    init(
        id: UUID = UUID(),
        session: Session? = nil,
        spot: Spot? = nil,
        areaNormalizedPx: Double = 0,
        meanLuminance: Double = 0,
        boundingRect: CGRect = .zero,
        date: Date = Date()
    ) {
        self.id = id
        self.session = session
        self.spot = spot
        self.areaNormalizedPx = areaNormalizedPx
        self.meanLuminance = meanLuminance
        self.rectX = boundingRect.origin.x
        self.rectY = boundingRect.origin.y
        self.rectWidth = boundingRect.width
        self.rectHeight = boundingRect.height
        self.date = date
    }

    var boundingRect: CGRect {
        get {
            CGRect(x: rectX, y: rectY, width: rectWidth, height: rectHeight)
        }
        set {
            rectX = newValue.origin.x
            rectY = newValue.origin.y
            rectWidth = newValue.width
            rectHeight = newValue.height
        }
    }

    var areaChangeDescription: String {
        String(format: "%.4f normalized area", areaNormalizedPx)
    }

    var luminanceDescription: String {
        String(format: "L*=%.1f", meanLuminance)
    }
}
