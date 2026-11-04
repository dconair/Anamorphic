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

    // Bildanalyse + Vorschläge
    var analysis: ImageAnalysis?
    var suggestions: [PresetSuggestion] = []
    var activePreset: StylePreset?
    var isAnalyzing = false
    /// Läuft hoch, wenn eine neue Analyse fertig ist (für die Animation der Anzeige).
    var analysisPulse = 0

    // Anzeige
    var previewImage: CGImage?
    var originalImage: CGImage?
    var showOriginal = false
    var sourceName = ""
    var sourcePixelSize: CGSize = .zero

    // Video
    var videoDuration: Double = 0
    var videoTime: Double = 0

    // Live-Wiedergabe
    var player: AVPlayer?
    var isPlaying = false
    var liveOutputSize: CGSize = .zero
    var liveActive: Bool { player != nil }

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
    @ObservationIgnored private var presetTask: Task<Void, Never>?
    @ObservationIgnored private let liveBox = LiveBox()
    @ObservationIgnored private var liveAsset: AVURLAsset?
    @ObservationIgnored private var liveItem: AVPlayerItem?
    @ObservationIgnored private var liveObserver: Any?
    @ObservationIgnored private var liveEndObserver: NSObjectProtocol?
    @ObservationIgnored private var liveRefreshTask: Task<Void, Never>?

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
        stopLive(refreshFrame: false)
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
        await analyzeCurrentFrame(autoApply: true)
        scheduleRender()
    }

    func loadVideo(url: URL, name: String) async {
        stopLive(refreshFrame: false)
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
            await analyzeCurrentFrame(autoApply: true)
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
        if let player {
            let current = player.currentTime().seconds
            if !isPlaying || abs(current - videoTime) > 0.35 {
                player.seek(to: CMTime(seconds: videoTime, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero)
            }
            return
        }
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

    // MARK: Analyse

    /// Analysiert das aktuelle Bild und wählt – wenn gewünscht – das passendste Preset.
    func analyzeCurrentFrame(autoApply: Bool) async {
        guard let src = sourceCI else { return }
        isAnalyzing = true
        let renderer = self.renderer
        let result = await Task.detached(priority: .userInitiated) {
            ImageAnalyzer.analyze(src, context: renderer.context)
        }.value
        analysis = result
        suggestions = ImageAnalyzer.suggestions(for: result)
        isAnalyzing = false
        analysisPulse += 1
        if autoApply, let best = suggestions.first {
            apply(preset: best.preset, animated: false)
        }
    }

    func reanalyze() {
        Task {
            await analyzeCurrentFrame(autoApply: false)
            scheduleRender()
        }
    }

    // MARK: Presets

    /// Wechselt das Preset. Zahlenwerte werden in ca. 0,45 s überblendet, sodass man die Regler
    /// laufen sieht und die Vorschau weich in den neuen Look übergeht.
    func apply(preset: StylePreset, animated: Bool = true) {
        var target = preset.settings
        target.lutSpace = settings.lutSpace
        // Titel-Einstellungen gehören nicht zum Look
        target.subtitleEnabled = settings.subtitleEnabled
        target.subtitleText = settings.subtitleText
        target.subtitleStyle = settings.subtitleStyle
        target.subtitleFont = settings.subtitleFont
        target.subtitleSize = settings.subtitleSize
        target.subtitlePosition = settings.subtitlePosition
        target.aspect = settings.aspect
        if let a = analysis { target = ImageAnalyzer.tuned(target, for: a) }

        activePreset = preset
        presetTask?.cancel()
        guard animated else {
            settings = target
            scheduleRender()
            return
        }
        let start = settings
        presetTask = Task {
            let steps = 14
            for i in 1...steps {
                if Task.isCancelled { return }
                let t = Double(i) / Double(steps)
                let eased = t * t * (3 - 2 * t)
                settings = AnamorphicSettings.blend(start, target, t: eased)
                scheduleRender()
                try? await Task.sleep(nanoseconds: 32_000_000)
            }
            settings = target
            scheduleRender()
        }
    }

    // MARK: Vorschau

    func scheduleRender() {
        if liveActive {
            refreshLive()
            return
        }
        renderTask?.cancel()
        guard let src = sourceCI else { return }
        let s = settings
        let lut = resolvedLUT()
        let mask = subjectMask
        let seed = Int(videoTime * 24)
        let time: Double? = media == .video ? videoTime : nil
        let renderer = self.renderer

        renderTask = Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if Task.isCancelled { return }
            let cg: CGImage? = await Task.detached(priority: .userInitiated) {
                // Im Video gibt es keine Motiv-Maske → derselbe Fallback wie im Export.
                let out = renderer.process(src, settings: s, lut: lut, subjectMask: mask, frameSeed: seed, time: time)
                return renderer.context.createCGImage(out, from: out.extent, format: .RGBA8,
                                                      colorSpace: AnamorphicRenderer.outputColorSpace)
            }.value
            if Task.isCancelled { return }
            previewImage = cg
        }
    }

    // MARK: Live-Wiedergabe

    /// Spielt das Video mit allen Effekten ab (Vorschau in max. 1280 px Breite, damit es flüssig bleibt).
    func startLive() {
        guard media == .video, let url = videoURL, player == nil else { return }
        let asset = AVURLAsset(url: url)
        liveAsset = asset
        liveBox.set(settings, lut: resolvedLUT())
        let box = liveBox
        let (composition, size) = VideoExporter.liveComposition(asset: asset, sourceSize: sourcePixelSize,
                                                                renderer: renderer) { box.get() }
        liveOutputSize = size
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = composition
        liveItem = item
        let p = AVPlayer(playerItem: item)
        p.seek(to: CMTime(seconds: videoTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)

        liveObserver = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.videoTime = min(max(0, t.seconds), self.videoDuration)
            }
        }
        liveEndObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                                 object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.player?.seek(to: .zero)
                self.videoTime = 0
            }
        }
        player = p
        p.play()
        isPlaying = true
    }

    func togglePlay() {
        guard let player else { startLive(); return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if videoTime >= videoDuration - 0.05 {
                player.seek(to: .zero)
                videoTime = 0
            }
            player.play()
            isPlaying = true
        }
    }

    /// Zurück zur Einzelbild-Vorschau.
    func stopLive(refreshFrame: Bool = true) {
        guard let player else { return }
        player.pause()
        if let obs = liveObserver { player.removeTimeObserver(obs) }
        if let end = liveEndObserver { NotificationCenter.default.removeObserver(end) }
        liveObserver = nil
        liveEndObserver = nil
        liveRefreshTask?.cancel()
        self.player = nil
        liveItem = nil
        liveAsset = nil
        isPlaying = false
        if refreshFrame {
            Task {
                await refreshVideoFrame()
                scheduleRender()
            }
        }
    }

    /// Neue Einstellungen für die laufende Wiedergabe. Regler wirken sofort, weil die Komposition die Werte
    /// bei jedem Bild neu liest. Nur wenn sich das Ausgabeformat ändert (oder im Pause-Zustand, um das
    /// stehende Bild neu zu rechnen), wird die Komposition ausgetauscht.
    private func refreshLive() {
        liveBox.set(settings, lut: resolvedLUT())
        liveRefreshTask?.cancel()
        liveRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000)
            if Task.isCancelled { return }
            guard let item = liveItem, let asset = liveAsset else { return }
            let scale = min(1, 1280 / max(1, sourcePixelSize.width))
            let scaled = CGSize(width: (sourcePixelSize.width * scale).rounded(), height: (sourcePixelSize.height * scale).rounded())
            let newSize = settings.geometry(for: scaled).outputSize
            let sizeChanged = abs(newSize.width - liveOutputSize.width) > 1 || abs(newSize.height - liveOutputSize.height) > 1
            guard sizeChanged || !isPlaying else { return }
            let box = liveBox
            let (composition, size) = VideoExporter.liveComposition(asset: asset, sourceSize: sourcePixelSize,
                                                                    renderer: renderer) { box.get() }
            liveOutputSize = size
            item.videoComposition = composition
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
