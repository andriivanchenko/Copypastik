import Foundation
import ImageIO
import Vision

/// On-device text recognition for image clips using Apple Vision.
///
/// Nothing leaves the Mac: the request runs locally through the Vision
/// framework and only the recognized string is kept. All work happens off the
/// main thread so clipboard capture and the picker never wait on it.
nonisolated enum TextRecognizer {
    /// Recognized text is capped so one huge screenshot cannot bloat history files.
    static let maxCharacters = 20_000
    /// Larger images are downscaled before recognition to bound memory use.
    static let maxPixelDimension = 4096

    /// Returns the recognized text, an empty string when the image has no
    /// text, or `nil` when recognition failed.
    static func recognizeText(in imageData: Data) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: recognizeTextSynchronously(in: imageData))
            }
        }
    }

    static func recognizeTextSynchronously(in imageData: Data) -> String? {
        guard let cgImage = makeBoundedCGImage(from: imageData) else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("[Copypastik] text recognition failed: \(error.localizedDescription)")
            return nil
        }

        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return normalize(lines: lines)
    }

    /// Joins recognized lines, drops blank ones and applies the length cap.
    static func normalize(lines: [String]) -> String {
        let joined = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return String(joined.prefix(maxCharacters))
    }

    private static func makeBoundedCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? Int) ?? 0

        if max(width, height) > maxPixelDimension {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
