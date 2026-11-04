import Foundation
import CoreImage
import Vision

/// Kennzahlen eines Bildes (aus einer kleinen Kopie berechnet, in Millisekunden).
struct ImageAnalysis: Equatable, Sendable {
    var meanLuma = 0.5            // 0 … 1 (Gamma-Raum)
    var contrast = 0.5            // p95 − p5 der Luminanz
    var darkFraction = 0.0        // Anteil sehr dunkler Pixel
    var clippedFraction = 0.0     // Anteil ausgebrannter Pixel
    var saturation = 0.3
    var warmth = 0.0              // R − B (Gamma-Raum), > 0 = warm
    var lightSourceCount = 0      // kleine, nahezu ausgebrannte Punkte
    var edgeDensity = 0.03        // mittlere Kantenstärke; klein = weich / flache Schärfentiefe
    var faceCount = 0
    var faceCoverage = 0.0        // Flächenanteil des größten Gesichts

    var isNight: Bool { meanLuma < 0.30 }
    var hasLightSources: Bool { lightSourceCount >= 1 }
    var isSoft: Bool { edgeDensity < 0.018 }
}

struct PresetSuggestion: Identifiable, Equatable {
    let preset: StylePreset
    let score: Double            // 0 … 1
    let reason: String
    var id: String { preset.rawValue }
}

enum ImageAnalyzer {

    static func analyze(_ image: CIImage, context: CIContext) -> ImageAnalysis {
        let ext = image.extent
        guard ext.width > 1, ext.height > 1 else { return ImageAnalysis() }

        // Auf ~192 px Breite verkleinern, nach sRGB-RGBA8 rendern
        let scale = min(1.0, 192.0 / ext.width)
        let small = image
            .transformed(by: CGAffineTransform(translationX: -ext.minX, y: -ext.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let w = max(2, Int(small.extent.width.rounded()))
        let h = max(2, Int(small.extent.height.rounded()))
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        var buf = [UInt8](repeating: 0, count: w * h * 4)
        context.render(small, toBitmap: &buf, rowBytes: w * 4, bounds: rect, format: .RGBA8, colorSpace: space)

        var luma = [Double](repeating: 0, count: w * h)
        var sumR = 0.0, sumB = 0.0, sumSat = 0.0
        for i in 0..<(w * h) {
            let r = Double(buf[i * 4]) / 255, g = Double(buf[i * 4 + 1]) / 255, b = Double(buf[i * 4 + 2]) / 255
            luma[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
            sumR += r
            sumB += b
            let mx = max(r, g, b), mn = min(r, g, b)
            sumSat += mx > 0.001 ? (mx - mn) / mx : 0
        }
        let n = Double(w * h)

        let sorted = luma.sorted()
        func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))] }

        var a = ImageAnalysis()
        a.meanLuma = luma.reduce(0, +) / n
        a.contrast = percentile(0.95) - percentile(0.05)
        a.darkFraction = Double(luma.filter { $0 < 0.12 }.count) / n
        a.clippedFraction = Double(luma.filter { $0 > 0.97 }.count) / n
        a.saturation = sumSat / n
        a.warmth = (sumR - sumB) / n

        // Lichtquellen: helle Pixel, deren Umgebung deutlich dunkler ist (Lampen, Sonne). In dunklen Szenen
        // reicht schon etwas weniger Helligkeit, weil Kamera und Verkleinerung Lichter abschwächen.
        let night = a.meanLuma < 0.30
        let hot = night ? 0.85 : 0.94
        let surround = hot * 0.6
        var spots = 0
        for y in 4..<max(4, h - 4) {
            for x in 4..<max(4, w - 4) where luma[y * w + x] > hot {
                var sum = 0.0
                for dy in -4...4 { for dx in -4...4 { sum += luma[(y + dy) * w + (x + dx)] } }
                if sum / 81 < surround { spots += 1 }
            }
        }
        a.lightSourceCount = spots >= 3 ? max(1, spots / 3) : 0
        // Große Lichtquelle (Sonne im Bild): ein klar begrenzter, heller Fleck ohne dass die Szene überstrahlt
        if a.lightSourceCount == 0, a.clippedFraction > 0.002, a.clippedFraction < 0.12 {
            let bright = luma.filter { $0 > 0.94 }.count
            if Double(bright) / n > 0.002 { a.lightSourceCount = 1 }
        }

        // Kantendichte
        var grad = 0.0
        for y in 0..<(h - 1) {
            for x in 0..<(w - 1) {
                let l = luma[y * w + x]
                grad += abs(luma[y * w + x + 1] - l) + abs(luma[(y + 1) * w + x] - l)
            }
        }
        a.edgeDensity = grad / (2 * n)

        // Gesichter
        if let cg = context.createCGImage(small, from: rect, format: .RGBA8, colorSpace: space) {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            if (try? handler.perform([request])) != nil, let faces = request.results {
                a.faceCount = faces.count
                a.faceCoverage = faces.map { Double($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0
            }
        }
        return a
    }

    // MARK: Empfehlungen

    static func suggestions(for a: ImageAnalysis) -> [PresetSuggestion] {
        func c(_ v: Double) -> Double { v.clamped(0, 1) }
        var out = [PresetSuggestion]()

        let night = c((0.38 - a.meanLuma) / 0.25)
        let nightScore = 0.65 * night + (a.hasLightSources ? 0.25 * night + 0.1 : 0) + 0.1 * c(a.darkFraction)
        out.append(PresetSuggestion(
            preset: .nightCity, score: c(nightScore),
            reason: a.hasLightSources && a.isNight ? "Dunkle Szene mit Lichtquellen"
                : a.isNight ? "Dunkle, kühle Szene" : "Wenig Licht"))

        let warm = c((a.warmth - 0.04) / 0.14)
        let lowLight = c((0.6 - a.meanLuma) / 0.35)
        out.append(PresetSuggestion(
            preset: .tungsten, score: c(warm * (0.5 + 0.5 * lowLight)),
            reason: "Warmes Kunstlicht"))

        let bright = c((a.meanLuma - 0.35) / 0.3)
        out.append(PresetSuggestion(
            preset: .goldenHour, score: c(warm * bright),
            reason: "Warme, helle Szene"))

        let lowSat = c((0.30 - a.saturation) / 0.2)
        let lowContrast = c((0.55 - a.contrast) / 0.3)
        out.append(PresetSuggestion(
            preset: .softFilm, score: c(0.5 * lowSat + 0.5 * lowContrast),
            reason: "Ruhige, entsättigte Szene"))

        out.append(PresetSuggestion(
            preset: .natural, score: c(0.45 + (a.faceCount > 0 ? 0.2 : 0)),
            reason: a.faceCount > 0 ? "Gesicht im Bild, natürlich halten" : "Ausgewogene Szene"))

        return out.sorted { $0.score > $1.score }
    }

    /// Passt ein Preset an das Bild an: Flares nur bei echten Lichtquellen, Gesichter schonen,
    /// schon weiche Bilder bekommen weniger Bokeh, extreme Belichtung wird leicht ausgeglichen.
    static func tuned(_ base: AnamorphicSettings, for a: ImageAnalysis) -> AnamorphicSettings {
        var s = base
        if !a.hasLightSources { s.flareEnabled = false }
        if a.faceCount > 0 {
            s.desqueeze = min(s.desqueeze, 1.1)
            s.edgeStretch = min(s.edgeStretch, 0.4)
            s.expansion = min(s.expansion, 1.08)
        }
        // Viel Feinstruktur (Architektur, Laub): Randdehnung sichtbar als Verschmieren, daher zurücknehmen
        if a.edgeDensity > 0.04 { s.expansion = min(s.expansion, 1.08); s.edgeStretch = min(s.edgeStretch, 0.35) }
        if a.isSoft { s.bokehAmount *= 0.4 }
        if a.meanLuma < 0.22 { s.exposure += 0.3 }
        if a.meanLuma > 0.75 { s.exposure -= 0.25 }
        return s
    }
}

// MARK: - Interpolation (für animierte Preset-Wechsel)

extension AnamorphicSettings {
    /// Zahlen werden weich überblendet, Schalter und Auswahlfelder springen bei t = 0.5.
    static func blend(_ a: AnamorphicSettings, _ b: AnamorphicSettings, t: Double) -> AnamorphicSettings {
        var r = t < 0.5 ? a : b
        func m(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        r.verticalOffset = m(a.verticalOffset, b.verticalOffset)
        r.desqueeze = m(a.desqueeze, b.desqueeze)
        r.edgeStretch = m(a.edgeStretch, b.edgeStretch)
        r.expansion = m(a.expansion, b.expansion)
        r.squeeze = m(a.squeeze, b.squeeze)
        r.bokehAmount = m(a.bokehAmount, b.bokehAmount)
        r.highlightBoost = m(a.highlightBoost, b.highlightBoost)
        r.focusX = m(a.focusX, b.focusX)
        r.focusY = m(a.focusY, b.focusY)
        r.focusSize = m(a.focusSize, b.focusSize)
        r.focusFeather = m(a.focusFeather, b.focusFeather)
        r.flareThreshold = m(a.flareThreshold, b.flareThreshold)
        r.flareLength = m(a.flareLength, b.flareLength)
        r.flareIntensity = m(a.flareIntensity, b.flareIntensity)
        r.halation = m(a.halation, b.halation)
        r.aberration = m(a.aberration, b.aberration)
        r.edgeSoftness = m(a.edgeSoftness, b.edgeSoftness)
        r.lookIntensity = m(a.lookIntensity, b.lookIntensity)
        r.exposure = m(a.exposure, b.exposure)
        r.warmth = m(a.warmth, b.warmth)
        r.tint = m(a.tint, b.tint)
        r.highlights = m(a.highlights, b.highlights)
        r.shadows = m(a.shadows, b.shadows)
        r.contrast = m(a.contrast, b.contrast)
        r.saturation = m(a.saturation, b.saturation)
        r.subtitleSize = m(a.subtitleSize, b.subtitleSize)
        r.subtitleSoftness = m(a.subtitleSoftness, b.subtitleSoftness)
        r.subtitlePosition = m(a.subtitlePosition, b.subtitlePosition)
        r.grain = m(a.grain, b.grain)
        r.grainSize = m(a.grainSize, b.grainSize)
        r.vignette = m(a.vignette, b.vignette)
        return r
    }
}
