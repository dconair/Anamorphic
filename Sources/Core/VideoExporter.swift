import Foundation
import AVFoundation
import CoreImage

enum VideoExportError: LocalizedError {
    case noVideoTrack
    case sessionUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "In der Datei wurde keine Videospur gefunden."
        case .sessionUnavailable: return "Der Export konnte auf diesem Gerät nicht gestartet werden."
        case .failed(let m): return "Export fehlgeschlagen: \(m)"
        }
    }
}

enum VideoExporter {

    /// Rendert das komplette Video mit der Anamorphic-Pipeline. Ton bleibt unverändert erhalten.
    /// Der Export läuft komplett über Core Image auf der GPU (AVVideoComposition).
    static func export(url: URL,
                       settings: AnamorphicSettings,
                       lut: CubeLUT?,
                       renderer: AnamorphicRenderer,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoExportError.noVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let sourceSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let geometry = settings.geometry(for: sourceSize)

        // Hinweis: Die Convenience-Initialisierung berücksichtigt die Drehung der Spur (preferredTransform),
        // `request.sourceImage` ist also bereits aufrecht. (In iOS 16 / macOS 13 als deprecated markiert,
        // funktioniert aber weiterhin und ist auf allen Zielsystemen verfügbar.)
        let composition = AVMutableVideoComposition(asset: asset) { request in
            let seed = Int((request.compositionTime.seconds * 24).rounded())
            let out = renderer.process(request.sourceImage,
                                       settings: settings,
                                       lut: lut,
                                       subjectMask: nil,   // Ellipse statt Motiv-Maske: pro Frame deutlich schneller
                                       frameSeed: seed)
            request.finish(with: out, context: renderer.context)
        }
        composition.renderSize = geometry.outputSize
        // Ausgabe immer als SDR Rec.709. HDR-Material (HLG / Dolby Vision) wird dabei von
        // AVFoundation in SDR umgerechnet, bevor es in die Pipeline kommt.
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let preset = AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality)
            ? AVAssetExportPresetHEVCHighestQuality
            : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw VideoExportError.sessionUnavailable
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Anamorphic-\(UUID().uuidString.prefix(8)).mov")
        try? FileManager.default.removeItem(at: outURL)
        session.outputURL = outURL
        session.outputFileType = .mov
        session.videoComposition = composition

        let poller = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { poller.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                session.exportAsynchronously {
                    switch session.status {
                    case .completed:
                        progress(1)
                        cont.resume(returning: outURL)
                    case .cancelled:
                        cont.resume(throwing: CancellationError())
                    default:
                        cont.resume(throwing: VideoExportError.failed(session.error?.localizedDescription ?? "unbekannter Fehler"))
                    }
                }
            }
        } onCancel: {
            session.cancelExport()
        }
    }

    /// Einzelbild für die Vorschau (verkleinert, aufrecht).
    static func frame(of url: URL, at seconds: Double, maxDimension: CGFloat = 1800) async throws -> CIImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        let (cg, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        return CIImage(cgImage: cg)
    }
}
