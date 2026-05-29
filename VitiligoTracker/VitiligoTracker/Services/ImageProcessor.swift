import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import SwiftData
import UIKit
import Accelerate

struct SpotRegion {
    let normalizedCenter: CGPoint
    let normalizedBounds: CGRect
    let normalizedArea: Double
    let meanLuminance: Double
}

enum ImageProcessorError: LocalizedError {
    case imageLoadFailed
    case noFaceDetected
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed:
            return "Failed to load image. Please try another photo."
        case .noFaceDetected:
            return "No face detected in the photo. Please ensure your face is clearly visible and well-lit."
        case .processingFailed(let msg):
            return "Processing failed: \(msg)"
        }
    }
}

class ImageProcessor {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Main Entry Point

    func analyzePhoto(
        at url: URL,
        existingSpots: [Spot],
        modelContext: ModelContext
    ) async throws -> (session: Session, newMeasurements: [SpotMeasurement]) {

        // Load image
        let ciImage = try loadCIImage(from: url)

        // Detect face
        let (boundingBox, landmarks) = try await detectFace(in: ciImage)

        // Crop to face region
        let faceImage = cropToFace(image: ciImage, boundingBox: boundingBox)

        // Detect hypopigmented spots
        let spotRegions = try detectHypopigmentedRegions(in: faceImage, landmarks: landmarks)

        // Save face-cropped image
        let savedPath = try saveFaceImage(faceImage, originalURL: url)

        // Create session
        let session = Session(
            date: Date(),
            photoPath: savedPath,
            treatmentNotes: "",
            uvMinutes: 0,
            medicineDose: ""
        )
        modelContext.insert(session)

        // Match regions to existing spots
        let matches = matchToExistingSpots(detected: spotRegions, existing: existingSpots)

        var newMeasurements: [SpotMeasurement] = []

        for (region, existingSpot) in matches {
            let spot: Spot
            if let existing = existingSpot {
                spot = existing
            } else {
                // Create new spot
                let label = labelForLocation(
                    normalizedPoint: region.normalizedCenter,
                    landmarks: landmarks
                )
                let newSpot = Spot(
                    label: label,
                    normalizedX: region.normalizedCenter.x,
                    normalizedY: region.normalizedCenter.y,
                    firstSeenDate: Date()
                )
                modelContext.insert(newSpot)
                spot = newSpot
            }

            let measurement = SpotMeasurement(
                session: session,
                spot: spot,
                areaNormalizedPx: region.normalizedArea,
                meanLuminance: region.meanLuminance,
                boundingRect: region.normalizedBounds,
                date: Date()
            )
            modelContext.insert(measurement)
            newMeasurements.append(measurement)
        }

        return (session, newMeasurements)
    }

    // MARK: - Step 1: Load Image

    func loadCIImage(from url: URL) throws -> CIImage {
        // Handle HEIC, JPEG, PNG via CIImage directly
        if let image = CIImage(contentsOf: url) {
            return image
        }
        // Fallback: try loading as UIImage first
        guard let uiImage = UIImage(contentsOfFile: url.path),
              let cgImage = uiImage.cgImage else {
            throw ImageProcessorError.imageLoadFailed
        }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Step 2: Face Detection

    func detectFace(in image: CIImage) async throws -> (boundingBox: CGRect, landmarks: VNFaceLandmarks2D?) {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceLandmarksRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: ImageProcessorError.processingFailed(error.localizedDescription))
                    return
                }
                guard let results = request.results as? [VNFaceObservation],
                      let face = results.first else {
                    continuation.resume(throwing: ImageProcessorError.noFaceDetected)
                    return
                }

                // VNFaceObservation boundingBox is normalized (0-1), origin at bottom-left
                // Convert to top-left origin for our use
                let bbox = face.boundingBox
                let converted = CGRect(
                    x: bbox.origin.x,
                    y: 1.0 - bbox.origin.y - bbox.height,
                    width: bbox.width,
                    height: bbox.height
                )
                continuation.resume(returning: (converted, face.landmarks))
            }

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ImageProcessorError.processingFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Step 3: Crop to Face

    func cropToFace(image: CIImage, boundingBox: CGRect) -> CIImage {
        let imageExtent = image.extent
        let padding: CGFloat = 0.20

        // boundingBox is in normalized coords (top-left origin)
        // Convert to pixel coords with padding
        let paddedX = max(0, boundingBox.origin.x - padding * boundingBox.width)
        let paddedY = max(0, boundingBox.origin.y - padding * boundingBox.height)
        let paddedW = min(1.0, boundingBox.width * (1 + 2 * padding))
        let paddedH = min(1.0, boundingBox.height * (1 + 2 * padding))

        let cropRect = CGRect(
            x: paddedX * imageExtent.width,
            y: (1.0 - paddedY - paddedH) * imageExtent.height, // flip back to CIImage bottom-left
            width: paddedW * imageExtent.width,
            height: paddedH * imageExtent.height
        )

        let clampedRect = cropRect.intersection(imageExtent)
        return image.cropped(to: clampedRect)
    }

    // MARK: - Step 4: Detect Hypopigmented Regions

    func detectHypopigmentedRegions(
        in faceImage: CIImage,
        landmarks: VNFaceLandmarks2D?
    ) throws -> [SpotRegion] {

        guard let cgImage = context.createCGImage(faceImage, from: faceImage.extent) else {
            throw ImageProcessorError.processingFailed("Cannot create CGImage for analysis")
        }

        let width = cgImage.width
        let height = cgImage.height

        guard width > 0, height > 0 else {
            throw ImageProcessorError.processingFailed("Invalid image dimensions")
        }

        // Render to RGBA pixel buffer
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmapContext = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ImageProcessorError.processingFailed("Cannot create bitmap context")
        }

        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Convert sRGB pixels to LAB L* values
        var labL = [Float](repeating: 0, count: width * height)
        convertToLabLuminance(pixels: pixelData, labL: &labL, width: width, height: height)

        // Sample baseline skin tone from nose bridge area (typically less affected by vitiligo)
        let baselineLuminance = sampleBaselineLuminance(
            labL: labL,
            width: width,
            height: height,
            landmarks: landmarks,
            faceImageExtent: faceImage.extent
        )

        // Threshold: pixels > baselineL + 15 LAB units are potentially depigmented
        let threshold: Float = 15.0
        var binaryMask = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            binaryMask[i] = labL[i] > baselineLuminance + threshold ? 1 : 0
        }

        // Morphological erosion to remove noise (3x3 kernel)
        let eroded = morphologicalErode(mask: binaryMask, width: width, height: height, radius: 2)
        // Dilate to restore size
        let dilated = morphologicalDilate(mask: eroded, width: width, height: height, radius: 3)

        // Connected components analysis
        let regions = connectedComponents(
            mask: dilated,
            labL: labL,
            width: width,
            height: height
        )

        // Filter small noise regions (< 0.3% of face area) and very large (> 60%)
        let faceArea = Double(width * height)
        let minArea = faceArea * 0.003
        let maxArea = faceArea * 0.60

        let filtered = regions.filter { r in
            let pixelArea = r.normalizedArea * faceArea
            return pixelArea >= minArea && pixelArea <= maxArea
        }

        return filtered
    }

    // MARK: - sRGB to LAB conversion

    private func sRGBToLab(r: Float, g: Float, b: Float) -> (L: Float, a: Float, b_: Float) {
        // Linearize sRGB
        func linearize(_ c: Float) -> Float {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let rl = linearize(r)
        let gl = linearize(g)
        let bl = linearize(b)

        // sRGB to XYZ (D65)
        let X = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375
        let Y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750
        let Z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041

        // Normalize by D65 white point
        let Xn: Float = 0.95047
        let Yn: Float = 1.00000
        let Zn: Float = 1.08883

        func f(_ t: Float) -> Float {
            t > 0.008856 ? pow(t, 1.0/3.0) : 7.787 * t + 16.0/116.0
        }

        let fx = f(X / Xn)
        let fy = f(Y / Yn)
        let fz = f(Z / Zn)

        let L = 116.0 * fy - 16.0
        let a = 500.0 * (fx - fy)
        let b_ = 200.0 * (fy - fz)

        return (L, a, b_)
    }

    private func convertToLabLuminance(pixels: [UInt8], labL: inout [Float], width: Int, height: Int) {
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let r = Float(pixels[idx]) / 255.0
                let g = Float(pixels[idx + 1]) / 255.0
                let b = Float(pixels[idx + 2]) / 255.0
                let (L, _, _) = sRGBToLab(r: r, g: g, b: b)
                labL[y * width + x] = L
            }
        }
    }

    private func sampleBaselineLuminance(
        labL: [Float],
        width: Int,
        height: Int,
        landmarks: VNFaceLandmarks2D?,
        faceImageExtent: CGRect
    ) -> Float {
        // Sample multiple safe zones and take the median
        var samples: [Float] = []

        // Nose bridge and cheeks are sampled in the center of the face
        // Use a grid of sample points away from typical vitiligo zones (eye corners, mouth corners)
        let sampleRegions: [(x: Double, y: Double, radius: Double)] = [
            (0.35, 0.55, 0.04), // left inner cheek
            (0.65, 0.55, 0.04), // right inner cheek
            (0.50, 0.45, 0.03), // nose bridge
            (0.50, 0.60, 0.03), // lower nose
        ]

        for region in sampleRegions {
            let centerX = Int(region.x * Double(width))
            let centerY = Int(region.y * Double(height))
            let radius = Int(region.radius * Double(min(width, height)))

            for dy in -radius...radius {
                for dx in -radius...radius {
                    let px = centerX + dx
                    let py = centerY + dy
                    guard px >= 0, px < width, py >= 0, py < height else { continue }
                    if dx*dx + dy*dy <= radius*radius {
                        samples.append(labL[py * width + px])
                    }
                }
            }
        }

        guard !samples.isEmpty else { return 60.0 }

        // Use the 40th percentile as baseline (most common "normal" skin tone in the sample)
        samples.sort()
        let idx = Int(Double(samples.count) * 0.40)
        return samples[min(idx, samples.count - 1)]
    }

    // MARK: - Morphological Operations

    private func morphologicalErode(mask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var allOn = true
                outer: for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx, ny = y + dy
                        if nx < 0 || nx >= width || ny < 0 || ny >= height {
                            allOn = false; break outer
                        }
                        if mask[ny * width + nx] == 0 {
                            allOn = false; break outer
                        }
                    }
                }
                result[y * width + x] = allOn ? 1 : 0
            }
        }
        return result
    }

    private func morphologicalDilate(mask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var anyOn = false
                outer: for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0 && nx < width && ny >= 0 && ny < height {
                            if mask[ny * width + nx] == 1 {
                                anyOn = true; break outer
                            }
                        }
                    }
                }
                result[y * width + x] = anyOn ? 1 : 0
            }
        }
        return result
    }

    // MARK: - Connected Components

    private func connectedComponents(
        mask: [UInt8],
        labL: [Float],
        width: Int,
        height: Int
    ) -> [SpotRegion] {
        var labels = [Int](repeating: -1, count: width * height)
        var currentLabel = 0

        // BFS flood fill
        for startY in 0..<height {
            for startX in 0..<width {
                let startIdx = startY * width + startX
                guard mask[startIdx] == 1 && labels[startIdx] == -1 else { continue }

                var queue: [(Int, Int)] = [(startX, startY)]
                labels[startIdx] = currentLabel
                var qHead = 0

                while qHead < queue.count {
                    let (cx, cy) = queue[qHead]; qHead += 1
                    for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let nIdx = ny * width + nx
                        if mask[nIdx] == 1 && labels[nIdx] == -1 {
                            labels[nIdx] = currentLabel
                            queue.append((nx, ny))
                        }
                    }
                }
                currentLabel += 1
            }
        }

        guard currentLabel > 0 else { return [] }

        // Compute bounding boxes, areas, mean luminance per component
        var minX = [Int](repeating: width, count: currentLabel)
        var maxX = [Int](repeating: 0, count: currentLabel)
        var minY = [Int](repeating: height, count: currentLabel)
        var maxY = [Int](repeating: 0, count: currentLabel)
        var pixelCount = [Int](repeating: 0, count: currentLabel)
        var lumSum = [Double](repeating: 0, count: currentLabel)

        for y in 0..<height {
            for x in 0..<width {
                let lbl = labels[y * width + x]
                guard lbl >= 0 else { continue }
                if x < minX[lbl] { minX[lbl] = x }
                if x > maxX[lbl] { maxX[lbl] = x }
                if y < minY[lbl] { minY[lbl] = y }
                if y > maxY[lbl] { maxY[lbl] = y }
                pixelCount[lbl] += 1
                lumSum[lbl] += Double(labL[y * width + x])
            }
        }

        let totalPixels = Double(width * height)
        var regions: [SpotRegion] = []

        for lbl in 0..<currentLabel {
            guard pixelCount[lbl] > 0 else { continue }
            let cx = Double(minX[lbl] + maxX[lbl]) / 2.0 / Double(width)
            let cy = Double(minY[lbl] + maxY[lbl]) / 2.0 / Double(height)
            let bx = Double(minX[lbl]) / Double(width)
            let by = Double(minY[lbl]) / Double(height)
            let bw = Double(maxX[lbl] - minX[lbl] + 1) / Double(width)
            let bh = Double(maxY[lbl] - minY[lbl] + 1) / Double(height)
            let area = Double(pixelCount[lbl]) / totalPixels
            let meanL = lumSum[lbl] / Double(pixelCount[lbl])

            regions.append(SpotRegion(
                normalizedCenter: CGPoint(x: cx, y: cy),
                normalizedBounds: CGRect(x: bx, y: by, width: bw, height: bh),
                normalizedArea: area,
                meanLuminance: meanL
            ))
        }

        return regions
    }

    // MARK: - Step 5: Match to Existing Spots

    func matchToExistingSpots(
        detected: [SpotRegion],
        existing: [Spot]
    ) -> [(region: SpotRegion, spot: Spot?)] {
        let matchThreshold = 0.15 // normalized distance

        return detected.map { region in
            var bestSpot: Spot? = nil
            var bestDistance = Double.infinity

            for spot in existing {
                let dx = region.normalizedCenter.x - spot.normalizedX
                let dy = region.normalizedCenter.y - spot.normalizedY
                let dist = sqrt(dx * dx + dy * dy)
                if dist < matchThreshold && dist < bestDistance {
                    bestDistance = dist
                    bestSpot = spot
                }
            }

            return (region, bestSpot)
        }
    }

    // MARK: - Step 6: Auto-Label Location

    func labelForLocation(
        normalizedPoint: CGPoint,
        landmarks: VNFaceLandmarks2D?
    ) -> String {
        let x = normalizedPoint.x
        let y = normalizedPoint.y

        // Divide face into zones based on normalized coordinates
        var zone: String
        if y < 0.25 {
            zone = "Forehead"
        } else if y < 0.45 {
            if x < 0.35 {
                zone = "Left Temple"
            } else if x > 0.65 {
                zone = "Right Temple"
            } else if y < 0.35 {
                zone = "Brow"
            } else {
                zone = "Eye Area"
            }
        } else if y < 0.65 {
            if x < 0.35 {
                zone = "Left Cheek"
            } else if x > 0.65 {
                zone = "Right Cheek"
            } else {
                zone = "Nose"
            }
        } else if y < 0.80 {
            if x < 0.40 {
                zone = "Left Cheek"
            } else if x > 0.60 {
                zone = "Right Cheek"
            } else {
                zone = "Upper Lip"
            }
        } else {
            zone = "Chin"
        }

        return zone
    }

    // MARK: - Save Image

    private func saveFaceImage(_ image: CIImage, originalURL: URL) throws -> String {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let photosDir = documentsURL.appendingPathComponent("SessionPhotos")
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

        let filename = "session_\(UUID().uuidString).jpg"
        let fileURL = photosDir.appendingPathComponent(filename)

        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw ImageProcessorError.processingFailed("Cannot render image to save")
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.85) else {
            throw ImageProcessorError.processingFailed("Cannot encode image as JPEG")
        }

        try jpegData.write(to: fileURL)
        return fileURL.path
    }
}
