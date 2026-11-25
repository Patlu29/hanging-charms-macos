import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Turns a picture the user drops or picks into charm artwork, on this Mac only.
enum PictureImporter {
    enum ImportError: LocalizedError {
        case unreadable, tooSmall, empty

        var errorDescription: String? {
            switch self {
            case .unreadable: "That file could not be read as a picture."
            case .tooSmall: "That picture is too small to make a charm from."
            case .empty: "Nothing was left after cutting out the subject."
            }
        }
    }

    static let supportedTypes: [UTType] = [.png, .jpeg, .heic, .webP, .tiff, .gif, .bmp, .svg, .pdf]
    static let maximumSide = 1024

    /// Loads and downsamples any picture ImageIO or NSImage can read.
    static func load(_ url: URL) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSide,
        ]
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           CGImageSourceGetCount(source) > 0,
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return try validated(image)
        }
        // Vector formats (SVG, PDF) through NSImage.
        guard let picture = NSImage(contentsOf: url) else { throw ImportError.unreadable }
        let side = CGFloat(maximumSide)
        let scale = side / max(picture.size.width, picture.size.height, 1)
        var rect = CGRect(x: 0, y: 0, width: picture.size.width * scale, height: picture.size.height * scale)
        guard let image = picture.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw ImportError.unreadable }
        return try validated(image)
    }

    private static func validated(_ image: CGImage) throws -> CGImage {
        guard image.width >= 24, image.height >= 24 else { throw ImportError.tooSmall }
        return image
    }

    /// Lifts the main subject out of a photo with Vision. Returns nil when Vision finds
    /// no subject, so the caller can fall back to the whole picture.
    static func cutOutSubject(_ image: CGImage) async -> CGImage? {
        await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
                guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
                let buffer = try result.generateMaskedImage(
                    ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true
                )
                let ciImage = CIImage(cvPixelBuffer: buffer)
                return CIContext().createCGImage(ciImage, from: ciImage.extent)
            } catch {
                return nil
            }
        }.value
    }

    /// Trims transparent margins so the charm hangs from the top of its subject.
    static func finish(_ image: CGImage) throws -> CGImage {
        guard let trimmed = AlphaTrim.trim(image) else { throw ImportError.empty }
        return trimmed
    }

    /// A sensible charm name from a file name.
    static func suggestedName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, base.count <= 32 else { return "My Charm" }
        return base.prefix(1).uppercased() + base.dropFirst()
    }
}
