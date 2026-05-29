import Foundation
import AVFoundation
import CoreImage
import Vision
import UIKit

enum VideoFrameExtractorError: LocalizedError {
    case cannotLoadAsset
    case noFramesExtracted
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .cannotLoadAsset:
            return "Cannot load video asset."
        case .noFramesExtracted:
            return "No frames could be extracted from the video."
        case .exportFailed:
            return "Failed to export the best frame."
        }
    }
}

class VideoFrameExtractor {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Main Entry Point

    func extractBestFrame(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        // Load duration
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw VideoFrameExtractorError.cannotLoadAsset
        }

        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else {
            throw VideoFrameExtractorError.cannotLoadAsset
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        // Sample 10 frames evenly throughout the video
        let sampleCount = 10
        var times: [CMTime] = []
        for i in 0..<sampleCount {
            let t = durationSeconds * Double(i) / Double(sampleCount - 1)
            let clamped = min(max(t, 0.1), durationSeconds - 0.1)
            times.append(CMTime(seconds: clamped, preferredTimescale: 600))
        }

        // Extract frames and score them
        var bestFrame: CGImage? = nil
        var bestScore: Double = -Double.infinity

        for time in times {
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let ciImage = CIImage(cgImage: cgImage)
                let score = await scoreFrame(cgImage: cgImage, ciImage: ciImage)
                if score > bestScore {
                    bestScore = score
                    bestFrame = cgImage
                }
            } catch {
                // Skip frames that can't be extracted
                continue
            }
        }

        guard let frame = bestFrame else {
            throw VideoFrameExtractorError.noFramesExtracted
        }

        return try saveFrame(frame)
    }

    // MARK: - Frame Scoring

    private func scoreFrame(cgImage: CGImage, ciImage: CIImage) async -> Double {
        let sharpness = sharpnessScore(of: ciImage)
        let faceConfidence = await detectFaceConfidence(in: ciImage)

        // Weighted: 40% sharpness, 60% face confidence
        return sharpness * 0.4 + faceConfidence * 100.0 * 0.6
    }

    // MARK: - Sharpness Score (Laplacian Variance)

    func sharpnessScore(of image: CIImage) -> Double {
        // Use Laplacian edge detection via CoreImage
        // High variance in edges = sharp image
        guard let edgeFilter = CIFilter(name: "CIEdges") else { return 0 }
        edgeFilter.setValue(image, forKey: kCIInputImageKey)
        edgeFilter.setValue(5.0, forKey: "inputIntensity")

        guard let edgeOutput = edgeFilter.outputImage else { return 0 }

        // Compute mean luminance of edge image as proxy for sharpness
        guard let areaFilter = CIFilter(name: "CIAreaAverage") else { return 0 }
        areaFilter.setValue(edgeOutput, forKey: kCIInputImageKey)
        areaFilter.setValue(CIVector(cgRect: edgeOutput.extent), forKey: "inputExtent")
        guard let avgOutput = areaFilter.outputImage else { return 0 }

        var pixel = [Float](repeating: 0, count: 4)
        context.render(
            avgOutput,
            toBitmap: &pixel,
            rowBytes: 16,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: nil
        )
        // Average of R, G, B channels as sharpness indicator
        let sharpness = Double((pixel[0] + pixel[1] + pixel[2]) / 3.0)
        return sharpness
    }

    // MARK: - Face Detection Confidence

    private func detectFaceConfidence(in image: CIImage) async -> Double {
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, _ in
                if let results = request.results as? [VNFaceObservation],
                   let best = results.first {
                    continuation.resume(returning: Double(best.confidence))
                } else {
                    continuation.resume(returning: 0.0)
                }
            }
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: 0.0)
            }
        }
    }

    // MARK: - Save Frame to Temp Directory

    private func saveFrame(_ cgImage: CGImage) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "extracted_frame_\(UUID().uuidString).jpg"
        let fileURL = tempDir.appendingPathComponent(filename)

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.90) else {
            throw VideoFrameExtractorError.exportFailed
        }
        try jpegData.write(to: fileURL)
        return fileURL
    }
}
