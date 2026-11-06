import AppKit
import Foundation
import UniformTypeIdentifiers

/// Builds the `NSItemProvider` used when a clip is dragged out of the Library.
///
/// - Text clips export plain text.
/// - Link clips export a URL first and the plain string as a fallback, so
///   apps that understand URLs get a link and everything else gets text.
/// - Image clips export PNG both as in-memory data (Notes, Slack, Figma
///   canvases) and as a lazily written file (apps and folders that accept
///   files). The file is a copy in the app's temporary directory; the
///   original clip is never touched.
enum LibraryDragProvider {
    static func itemProvider(for item: ClipboardHistoryItem) -> NSItemProvider {
        switch item.content {
        case .text(let text):
            return textProvider(for: text)
        case .image(let image):
            return imageProvider(for: image)
        }
    }

    private static func textProvider(for text: String) -> NSItemProvider {
        if let url = ClipTransform.webURL(from: text) {
            let provider = NSItemProvider(object: url as NSURL)
            provider.registerObject(text.trimmingCharacters(in: .whitespacesAndNewlines) as NSString, visibility: .all)
            return provider
        }
        return NSItemProvider(object: text as NSString)
    }

    private static func imageProvider(for image: ClipboardImage) -> NSItemProvider {
        let provider = NSItemProvider()
        let fileName = suggestedFileName(for: image)
        provider.suggestedName = (fileName as NSString).deletingPathExtension

        let data = image.data
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            do {
                let url = try writeTemporaryFile(data: data, fileName: fileName)
                // `false`: not opened in place, so the receiver gets its own copy.
                completion(url, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }

        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }

        return provider
    }

    static func suggestedFileName(for image: ClipboardImage) -> String {
        "Copypastik Image \(image.width)x\(image.height).png"
    }

    nonisolated static var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CopypastikDrag", isDirectory: true)
    }

    nonisolated private static func writeTemporaryFile(data: Data, fileName: String) throws -> URL {
        let directory = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Deletes drag exports left behind by earlier sessions.
    static func cleanUpTemporaryFiles() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}
