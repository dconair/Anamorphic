import SwiftUI
import Observation
import PhotosUI
import Photos
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

/// Film aus der Mediathek, als Datei in den temporären Ordner kopiert.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString.prefix(8)).\(ext)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case look, lens, flare, color, film, titles, export
    var id: String { rawValue }
    var title: String {
        switch self {
        case .look: return "Look"
        case .lens: return "Linse"
        case .flare: return "Flare"
        case .color: return "Farbe"
        case .film: return "Film"
        case .titles: return "Titel"
        case .export: return "Export"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    enum Media { case none, photo, video }

    // Zustand
    var media: Media = .none
    var settings = AnamorphicSettings()
    var customLUT: CubeLUT?
    var tab: InspectorTab = .look

    // Anzeige
    var previewImage: CGImage?
    var originalImage: CGImage?
    var showOriginal = false
    var sourceName = ""
    var sourcePixelSize: CGSize = .zero

    // Video
    var videoDuration: Double = 0
    var videoTime: Double = 0

    // Export
    var photoFormat: AnamorphicRenderer.PhotoFormat = .jpeg
    var isExporting = false
    var exportProgress: Double = 0
    var exportedURL: URL?
    var exportedIsVideo = false
    var notice: String?
    var errorMessage: String?

    // Intern
    @ObservationIgnored private let renderer = AnamorphicRenderer()
    @ObservationIgnored private var sourceCI: CIImage?
    @ObservationIgnored private var subjectMask: CIImage?
    @ObservationIgnored private var photoData: Data?
    @ObservationIgnored private var videoURL: URL?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?

    var hasMedia: Bool { media != .none }

    /// Ausgabegröße für die Anzeige im Readout.
    var outputSize: CGSize? {
        guard sourcePixelSize.width > 0 else { return nil }
        return settings.geometry(for: sourcePixelSize).outputSize
    }

    private func resolvedLUT() -> CubeLUT? {
        LookLibrary.resolve(id: settings.lookID, custom: customLUT)
    }

    // MARK: Laden

    func load(pickerItem: PhotosPickerItem) async {
        errorMessage = nil
        let isMovie = pickerItem.supportedContentTypes.contains { $0.conforms(to: .movie) }
        do {
            if isMovie {
                guard let movie = try await pickerItem.loadTransferable(type: PickedMovie.self) else { throw LoadError.unreadable }
                await loadVideo(url: movie.url, name: "Mediathek-Video")
            } else {
                guard let data = try await pickerItem.loadTransferable(type: Data.self) else { throw LoadError.unreadable }
                await loadPhoto(data: data, name: "Mediathek-Foto")
            }
        } catch {
            errorMessage = "Die Datei konnte nicht geladen werden."
        }
    }

    func open(fileURL: URL) async {
        errorMessage = nil
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }

        let type = UTType(filenameExtension: fileURL.pathExtension.lowercased())
        do {
            if type?.conforms(to: .movie) == true || type?.conforms(to: .audiovisualContent) == true {
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("import-\(UUID().uuidString.prefix(8)).\(fileURL.pathExtension)")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: fileURL, to: dest)
                await loadVideo(url: dest, name: fileURL.deletingPathExtension().lastPathComponent)
            } else if type?.conforms(to: .image) == true {
                let data = try Data(contentsOf: fileURL)
                await loadPhoto(data: data, name: fileURL.deletingPathExtension().lastPathComponent)
            } else {
                errorMessage = "Dieses Dateiformat wird nicht unterstützt."
            }
        } catch {
            errorMessage = "Die Datei konnte nicht gelesen werden."
        }
    }

    private enum LoadError: Error { case unreadable }

    private func resetExportState() {
        exportedURL = nil
        notice = nil
        exportProgress = 0
    }

    func loadPhoto(data: Data, name: String) async {
        guard let full = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            errorMessage = "Das Bild konnte nicht gelesen werden."
            return
        }
        resetExportState()
        let size = full.extent.size
        let renderer = self.renderer
        let prepared: (CIImage, CGImage?, CIImage?) = await Task.detached(priority: .userInitiated) {
            let small = Self.downscaled(full, maxDimension: 1800)
            let original = renderer.context.createCGImage(small, from: small.extent, format: .RGBA8,
                                                          colorSpace: AnamorphicRenderer.outputColorSpace)
            let mask = SubjectMask.generate(for: small)
            return (small, original, mask)
        }.value

        photoData = data
        videoURL = nil
        sourceCI = prepared.0
        originalImage = prepared.1
        subjectMask = prepared.2
        sourcePixelSize = size
        sourceName = name
        media = .photo
        scheduleRender()
    }

    func loadVideo(url: URL, name: String) async {
        resetExportState()
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                errorMessage = "In der Datei wurde keine Videospur gefunden."
                return
            }
            let natural = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let r = CGRect(origin: .zero, size: natural).applying(transform)

            videoURL = url
            photoData = nil
            subjectMask = nil
            videoDuration = max(0.1, duration.isFinite ? duration : 0.1)
            videoTime = min(1.0, videoDuration / 2)
            sourcePixelSize = CGSize(width: abs(r.width), height: abs(r.height))
            sourceName = name
            media = .video
            await refreshVideoFrame()
            scheduleRender()
        } catch {
            errorMessage = "Das Video konnte nicht geladen werden."
        }
    }

    private func refreshVideoFrame() async {
        guard let url = videoURL else { return }
        do {
            let frame = try await VideoExporter.frame(of: url, at: videoTime)
            sourceCI = frame
            let renderer = self.renderer
            originalImage = await Task.detached(priority: .userInitiated) {
                renderer.context.createCGImage(frame, from: frame.extent, format: .RGBA8,
                                               colorSpace: AnamorphicRenderer.outputColorSpace)
            }.value
        } catch {
            if !Task.isCancelled { errorMessage = "Das Vorschaubild konnte nicht geladen werden." }
        }
    }

    func videoTimeChanged() {
        frameTask?.cancel()
        frameTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            if Task.isCancelled { return }
            await refreshVideoFrame()
            if Task.isCancelled { return }
            scheduleRender()
        }
    }

    nonisolated private static func downscaled(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let e = image.extent
        let scale = min(1, maxDimension / max(e.width, e.height))
        guard scale < 1 else { return image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)) }
        let f = CIFilter.lanczosScaleTransform()
        f.inputImage = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        f.scale = Float(scale)
        f.aspectRatio = 1
        return f.outputImage ?? image
    }

    // MARK: LUT

    func importLUT(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let name = url.deletingPathExtension().lastPathComponent
            customLUT = try CubeLUT.parse(text, fallbackTitle: name)
            settings.lookID = "custom"
            settings.lookIntensity = 1.0
            notice = "LUT „\(customLUT?.title ?? name)“ geladen (\(customLUT?.size ?? 0)³)"
        } catch let e as CubeLUTError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "Die LUT konnte nicht gelesen werden."
        }
    }

    func apply(preset: StylePreset) {
        var s = preset.settings
        s.lutSpace = settings.lutSpace
        settings = s
    }

    // MARK: Vorschau

    func scheduleRender() {
        renderTask?.cancel()
        guard let src = sourceCI else { return }
        let s = settings
        let lut = resolvedLUT()
        let mask = subjectMask
        let seed = Int(videoTime * 24)
        let renderer = self.renderer

        renderTask = Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if Task.isCancelled { return }
            let cg: CGImage? = await Task.detached(priority: .userInitiated) {
                // Im Video gibt es keine Motiv-Maske → derselbe Fallback wie im Export.
                let out = renderer.process(src, settings: s, lut: lut, subjectMask: mask, frameSeed: seed)
                return renderer.context.createCGImage(out, from: out.extent, format: .RGBA8,
                                                      colorSpace: AnamorphicRenderer.outputColorSpace)
            }.value
            if Task.isCancelled { return }
            previewImage = cg
        }
    }

    // MARK: Export

    func startExport() {
        guard !isExporting, hasMedia else { return }
        isExporting = true
        exportProgress = 0
        exportedURL = nil
        notice = nil
        errorMessage = nil

        let s = settings
        let lut = resolvedLUT()
        let renderer = self.renderer
        let format = photoFormat

        exportTask = Task {
            defer { isExporting = false }
            do {
                switch media {
                case .photo:
                    guard let data = photoData else { return }
                    let mask = subjectMask
                    let url = try await Task.detached(priority: .userInitiated) { () -> URL in
                        guard let full = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
                            throw VideoExportError.failed("Bild nicht lesbar")
                        }
                        let out = renderer.process(full, settings: s, lut: lut, subjectMask: mask, frameSeed: 1)
                        let encoded = try renderer.encode(out, format: format)
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("Anamorphic-\(UUID().uuidString.prefix(6)).\(format.fileExtension)")
                        try encoded.write(to: url)
                        return url
                    }.value
                    exportedURL = url
                    exportedIsVideo = false
                    exportProgress = 1
                case .video:
                    guard let src = videoURL else { return }
                    let url = try await VideoExporter.export(url: src, settings: s, lut: lut, renderer: renderer) { p in
                        Task { @MainActor [weak self] in self?.exportProgress = p }
                    }
                    exportedURL = url
                    exportedIsVideo = true
                    exportProgress = 1
                case .none:
                    break
                }
            } catch is CancellationError {
                notice = "Export abgebrochen"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelExport() { exportTask?.cancel() }

    func saveToPhotos() async {
        guard let url = exportedURL else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            errorMessage = "Kein Zugriff auf die Fotos-Mediathek. Bitte in den Einstellungen erlauben."
            return
        }
        let isVideo = exportedIsVideo
        do {
            try await PHPhotoLibrary.shared().performChanges {
                if isVideo {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }
            notice = "In Fotos gesichert"
        } catch {
            errorMessage = "Das Sichern in Fotos ist fehlgeschlagen."
        }
    }
}
