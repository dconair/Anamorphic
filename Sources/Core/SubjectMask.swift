import Foundation
import CoreImage
import Vision
import CoreImage.CIFilterBuiltins

/// Motiv-Maske über Apples Vision-Framework (iOS 17 / macOS 14).
/// Weiß = Motiv (bleibt scharf), Schwarz = Hintergrund (bekommt Bokeh).
/// Gibt `nil` zurück, wenn kein Motiv erkannt wurde – die Pipeline fällt dann auf die Ellipse zurück.
enum SubjectMask {
    static func generate(for image: CIImage, maxDimension: CGFloat = 1024) -> CIImage? {
        let ext = image.extent
        guard ext.width > 0, ext.height > 0 else { return nil }
        let normalized = image.transformed(by: CGAffineTransform(translationX: -ext.minX, y: -ext.minY))
        let scale = min(1, maxDimension / max(ext.width, ext.height))
        let small = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: small, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
            let raw = CIImage(cvPixelBuffer: buffer)

            // Einkanal-Puffer → Graustufen (sonst erscheint die Maske nur im Rotkanal)
            let f = CIFilter.colorMatrix()
            f.inputImage = raw
            f.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            f.gVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            f.bVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            f.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            f.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            return f.outputImage
        } catch {
            return nil
        }
    }
}


