import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

/// Die komplette Bild-Pipeline (Foto-Export, Vorschau und jeder Video-Frame laufen hier durch).
///
/// Reihenfolge – bewusst wie in der Realität, vom Glas zum Sensor zur Farbkorrektur:
///   1. Bokeh (in "gequetschtem" Raum → ovale Scheiben, Motiv bleibt scharf)
///   2. Laterale Farbsäume zum Rand
///   3. Streak-Flares + Halation von echten Lichtquellen
///   4. (optional) Entzerren, dann Zuschnitt auf das Zielformat
///   5. Farbe: Belichtung, Weißabgleich, Lichter/Tiefen, LUT, Kontrast/Sättigung
///   6. Vignette, Korn
///   7. Untertitel (cinema / klassisch / brat)
///
/// Alle Konstanten, die den Charakter bestimmen, stehen in `Tuning` und sind an einer Stelle justierbar.
final class AnamorphicRenderer: @unchecked Sendable {

    enum Tuning {
        /// Faktor Bokeh-Radius (relativ zur Bildbreite) bei Stärke = 1
        static let bokehRadiusPerWidth = 0.018
        /// Streaks werden auf diese Größe verkleinert, bevor sie verwischt werden (Performance)
        static let streakDownscale = 0.25
        /// Maximale Motion-Blur-Länge von Core Image (px im verkleinerten Bild)
        static let streakMaxRadius = 100.0
        /// Streaks werden nie heller als dieser Wert (vor Intensität)
        static let streakClamp = 1.5
        /// Chromatische Aberration: maximale Skalendifferenz R/B bei Stärke = 1
        static let aberrationMaxScale = 0.004
    }

    static let outputColorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    let context: CIContext

    init(context: CIContext? = nil) {
        self.context = context ?? CIContext(options: [.highQualityDownsample: true])
    }

    // MARK: Einstieg

    func outputSize(for input: CGSize, settings: AnamorphicSettings) -> CGSize {
        settings.geometry(for: input).outputSize
    }

    func process(_ source: CIImage,
                 settings s: AnamorphicSettings,
                 lut: CubeLUT?,
                 subjectMask: CIImage?,
                 frameSeed: Int) -> CIImage {
        var img = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
        let inputExtent = img.extent

        // 1–3: Optik
        if s.bokehEnabled && s.bokehAmount > 0.01 {
            img = bokeh(img, s, subjectMask: subjectMask)
        }
        if s.aberration > 0.01 {
            img = chromaticAberration(img, amount: s.aberration * Tuning.aberrationMaxScale)
        }
        if s.flareEnabled || s.halation > 0.01 {
            img = flares(img, s)
        }

        // 4: Geometrie
        let geo = s.geometry(for: inputExtent.size)
        if s.desqueeze > 1.0001 {
            img = img.transformed(by: CGAffineTransform(scaleX: s.desqueeze, y: 1))
        }
        img = img.cropped(to: geo.crop)
            .transformed(by: CGAffineTransform(translationX: -geo.crop.minX, y: -geo.crop.minY))
        let outRect = CGRect(origin: .zero, size: geo.crop.size)

        // 5: Farbe
        img = grade(img, s, lut: lut)

        // 6: Film
        if s.vignette > 0.01 { img = vignette(img, amount: s.vignette, rect: outRect) }
        if s.grain > 0.01 { img = grain(img, s, rect: outRect, seed: frameSeed) }

        // 7: Untertitel liegen ganz oben (nach Grading und Korn), wie in der echten Postproduktion
        if let subs = SubtitleRenderer.layer(for: s, size: outRect.size) {
            img = subs.composited(over: img)
        }

        return img.cropped(to: outRect)
    }

    // MARK: Hilfsfunktionen

    /// Additiv mischen und Alpha wieder auf 1 setzen (Addition würde Alpha sonst verdoppeln).
    private func add(_ a: CIImage, _ b: CIImage) -> CIImage {
        let f = CIFilter.additionCompositing()
        f.inputImage = b
        f.backgroundImage = a
        return (f.outputImage ?? a).settingAlphaOne(in: a.extent)
    }

    private func matrix(_ img: CIImage, r: [Double], g: [Double], b: [Double], bias: [Double] = [0, 0, 0, 0]) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = img
        f.rVector = CIVector(x: r[0], y: r[1], z: r[2], w: r[3])
        f.gVector = CIVector(x: g[0], y: g[1], z: g[2], w: g[3])
        f.bVector = CIVector(x: b[0], y: b[1], z: b[2], w: b[3])
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        f.biasVector = CIVector(x: bias[0], y: bias[1], z: bias[2], w: bias[3])
        return f.outputImage ?? img
    }

    private func toGamma(_ img: CIImage) -> CIImage { img.applyingFilter("CILinearToSRGBToneCurve") }
    private func toLinear(_ img: CIImage) -> CIImage { img.applyingFilter("CISRGBToneCurveToLinear") }

    private func scaled(_ img: CIImage, by k: Double) -> CIImage {
        matrix(img, r: [k, 0, 0, 0], g: [0, k, 0, 0], b: [0, 0, k, 0])
    }

    private func gaussian(_ img: CIImage, radius: Double) -> CIImage {
        let ext = img.extent
        let f = CIFilter.gaussianBlur()
        f.inputImage = img.clampedToExtent()
        f.radius = Float(max(0.01, radius))
        return (f.outputImage ?? img).cropped(to: ext)
    }

    /// Alles oberhalb der Schwelle (Schwelle in Anzeige-Helligkeit, Berechnung linear).
    private func highlights(of img: CIImage, threshold: Double, gain: Double) -> CIImage {
        let t = pow(threshold.clamped(0, 1), 2.2)
        let m = matrix(img,
                       r: [gain, 0, 0, 0], g: [0, gain, 0, 0], b: [0, 0, gain, 0],
                       bias: [-t * gain, -t * gain, -t * gain, 0])
        let c = CIFilter.colorClamp()
        c.inputImage = m
        c.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        c.maxComponents = CIVector(x: 16, y: 16, z: 16, w: 1)
        return c.outputImage ?? m
    }

    // MARK: 1 – Bokeh

    private func bokeh(_ img: CIImage, _ s: AnamorphicSettings, subjectMask: CIImage?) -> CIImage {
        let extent = img.extent
        let w = extent.width

        // Ovale Scheiben entstehen, indem man im horizontal gestauchten Raum rund unscharf macht
        // und danach wieder streckt – genau wie ein Anamorphot. Eine eventuelle Entzerrung
        // (desqueeze) trägt bereits zur Ovalität bei und wird angerechnet.
        let e = max(1.0, s.bokehOval / max(1.0, s.desqueeze))
        let radius = s.bokehAmount.clamped(0, 1) * Tuning.bokehRadiusPerWidth * w / e

        // Lichter vor dem Verwischen anheben, damit helle Punkte zu klaren Scheiben werden.
        var base = img
        if s.highlightBoost > 0.01 {
            let hl = highlights(of: img, threshold: 0.85, gain: 3.0)
            base = add(img, scaled(hl, by: s.highlightBoost * 2.5))
        }

        let squeezed = base.transformed(by: CGAffineTransform(scaleX: 1.0 / e, y: 1))
        let f = CIFilter.bokehBlur()
        f.inputImage = squeezed.clampedToExtent()
        f.radius = Float(max(0.5, radius))
        f.ringAmount = 0.08
        f.ringSize = 0.1
        f.softness = 1.0
        var blurred = (f.outputImage ?? squeezed).cropped(to: squeezed.extent)
        blurred = blurred.transformed(by: CGAffineTransform(scaleX: e, y: 1)).cropped(to: extent)

        let mask = focusMask(for: extent, s, subjectMask: subjectMask)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = img            // wo Maske weiß ist → scharf
        blend.backgroundImage = blurred
        blend.maskImage = mask
        return (blend.outputImage ?? img).cropped(to: extent)
    }

    private func focusMask(for extent: CGRect, _ s: AnamorphicSettings, subjectMask: CIImage?) -> CIImage {
        let w = extent.width, h = extent.height

        if s.focusMode == .subject, let m = subjectMask, m.extent.width > 0, m.extent.height > 0 {
            let fitted = m
                .transformed(by: CGAffineTransform(translationX: -m.extent.minX, y: -m.extent.minY))
                .transformed(by: CGAffineTransform(scaleX: w / m.extent.width, y: h / m.extent.height))
                .cropped(to: extent)
            // Weicher Übergang statt harter Schnittkante; zusätzlich etwas aufweiten, damit
            // Haare und Ränder nicht angeschnitten werden.
            let grow = CIFilter.morphologyMaximum()
            grow.inputImage = fitted.clampedToExtent()
            grow.radius = Float(max(1, w * 0.002))
            let grown = (grow.outputImage ?? fitted).cropped(to: extent)
            return gaussian(grown, radius: 1 + s.focusFeather.clamped(0, 1) * w * 0.012)
        }

        // Elliptische Schärfezone, an das Bildformat angepasst
        let k = w / h
        let cx = s.focusX.clamped(0, 1) * w
        let cy = (1 - s.focusY.clamped(0, 1)) * h
        let r0 = s.focusSize.clamped(0.05, 1) * 0.5 * h
        let r1 = r0 + (0.12 + s.focusFeather.clamped(0, 1) * 0.7) * h

        let g = CIFilter.radialGradient()
        g.center = CGPoint(x: cx / k, y: cy)
        g.radius0 = Float(r0)
        g.radius1 = Float(r1)
        g.color0 = CIColor(red: 1, green: 1, blue: 1)
        g.color1 = CIColor(red: 0, green: 0, blue: 0)
        let grad = g.outputImage ?? CIImage(color: .white)
        return grad.transformed(by: CGAffineTransform(scaleX: k, y: 1)).cropped(to: extent)
    }

    // MARK: 2 – Chromatische Aberration

    private func chromaticAberration(_ img: CIImage, amount a: Double) -> CIImage {
        let extent = img.extent
        let c = CGPoint(x: extent.midX, y: extent.midY)
        let base = img.clampedToExtent()

        func about(_ im: CIImage, _ k: Double) -> CIImage {
            let t = CGAffineTransform(translationX: c.x, y: c.y)
                .scaledBy(x: k, y: k)
                .translatedBy(x: -c.x, y: -c.y)
            return im.transformed(by: t)
        }

        let red = about(matrix(base, r: [1, 0, 0, 0], g: [0, 0, 0, 0], b: [0, 0, 0, 0]), 1 + a)
        let green = matrix(base, r: [0, 0, 0, 0], g: [0, 1, 0, 0], b: [0, 0, 0, 0])
        let blue = about(matrix(base, r: [0, 0, 0, 0], g: [0, 0, 0, 0], b: [0, 0, 1, 0]), 1 - a)

        // Maximum statt Addition: jeder Kanal ist in genau einem Teilbild ungleich 0 und Alpha bleibt 1.
        let m1 = CIFilter.maximumCompositing()
        m1.inputImage = red
        m1.backgroundImage = green
        let m2 = CIFilter.maximumCompositing()
        m2.inputImage = blue
        m2.backgroundImage = m1.outputImage ?? green
        return (m2.outputImage ?? img).cropped(to: extent)
    }

    // MARK: 3 – Flares & Halation

    private func flares(_ img: CIImage, _ s: AnamorphicSettings) -> CIImage {
        let extent = img.extent
        let w = extent.width
        var out = img

        // Nur kleine, sehr helle Lichtquellen streuen: Große helle Flächen (weiße Wand) werden
        // über eine "Top-Hat"-Differenz herausgerechnet.
        let hl = highlights(of: img, threshold: s.flareThreshold, gain: 4.0)
        let sources = isolateSmallSources(hl, width: w)

        if s.flareEnabled && s.flareIntensity > 0.01 && s.flareLength > 0.01 {
            let streak = streakLayer(from: sources, extent: extent, length: s.flareLength)
            let tint = s.flareTint.rgb
            let k = s.flareIntensity.clamped(0, 1) * 0.9
            let l: [Double] = [0.2126, 0.7152, 0.0722, 0]
            let tinted = matrix(streak,
                                r: l.map { $0 * tint.r * k },
                                g: l.map { $0 * tint.g * k },
                                b: l.map { $0 * tint.b * k })
            out = add(out, tinted)
        }

        if s.halation > 0.01 {
            // Warmer, roter Hof um Lichtquellen (Rückreflexion im Film/Glas)
            let glow = gaussian(sources, radius: w * 0.010)
            let k = s.halation.clamped(0, 1) * 0.55
            let warm = matrix(glow,
                              r: [k * 1.0, 0, 0, 0],
                              g: [0, k * 0.38, 0, 0],
                              b: [0, 0, k * 0.16, 0])
            out = add(out, warm)
        }
        return out
    }

    private func isolateSmallSources(_ hl: CIImage, width w: Double) -> CIImage {
        let local = gaussian(hl, radius: w * 0.012)
        // hl - local (negatives Bild addieren), danach auf ≥ 0 begrenzen
        let diff = add(hl, scaled(local, by: -1))
        let c = CIFilter.colorClamp()
        c.inputImage = diff
        c.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        c.maxComponents = CIVector(x: 16, y: 16, z: 16, w: 1)
        return c.outputImage ?? diff
    }

    private func streakLayer(from sources: CIImage, extent: CGRect, length: Double) -> CIImage {
        let ds = Tuning.streakDownscale
        let small = sources.transformed(by: CGAffineTransform(scaleX: ds, y: ds))
        let smallExtent = small.extent

        func pass(_ radius: Double, weight: Double) -> CIImage {
            let f = CIFilter.motionBlur()
            f.inputImage = small.clampedToExtent()
            f.radius = Float(max(1, radius))
            f.angle = 0
            let blurred = (f.outputImage ?? small).cropped(to: smallExtent)
            // Motion-Blur mittelt → Energie verteilt sich über die Länge. Gain gleicht das aus.
            return scaled(blurred, by: 0.45 * radius * weight)
        }

        let rLong = Tuning.streakMaxRadius * length.clamped(0.05, 1)
        let long = pass(rLong, weight: 0.7)
        let mid = pass(rLong * 0.35, weight: 0.5)
        var combined = add(long, mid)

        let clamp = CIFilter.colorClamp()
        clamp.inputImage = combined
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: Tuning.streakClamp, y: Tuning.streakClamp, z: Tuning.streakClamp, w: 1)
        combined = clamp.outputImage ?? combined

        return combined
            .transformed(by: CGAffineTransform(scaleX: 1 / ds, y: 1 / ds))
            .cropped(to: extent)
    }

    // MARK: 5 – Farbe

    private func grade(_ input: CIImage, _ s: AnamorphicSettings, lut: CubeLUT?) -> CIImage {
        var img = input

        if abs(s.exposure) > 0.001 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = img
            f.ev = Float(s.exposure)
            img = f.outputImage ?? img
        }

        if abs(s.warmth) > 0.001 || abs(s.tint) > 0.001 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = img
            // Neutral > Ziel (6500 K) wärmt das Bild auf.
            f.neutral = CIVector(x: 6500 + s.warmth * 1800, y: s.tint * 60)
            f.targetNeutral = CIVector(x: 6500, y: 0)
            img = f.outputImage ?? img
        }

        if abs(s.highlights) > 0.001 || abs(s.shadows) > 0.001 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = img
            f.highlightAmount = Float(1 + min(0, s.highlights) * 0.7)
            f.shadowAmount = Float(s.shadows)
            f.radius = 0
            img = f.outputImage ?? img
        }

        if let lut, s.lookIntensity > 0.001 {
            let f = CIFilter.colorCubeWithColorSpace()
            f.inputImage = img
            f.cubeDimension = Float(lut.size)
            f.cubeData = lut.cubeData
            f.colorSpace = s.lutSpace.cgColorSpace
            if let graded = f.outputImage {
                if s.lookIntensity < 0.999 {
                    let d = CIFilter.dissolveTransition()
                    d.inputImage = img
                    d.targetImage = graded
                    d.time = Float(s.lookIntensity)
                    img = d.outputImage ?? graded
                } else {
                    img = graded
                }
            }
        }

        if abs(s.contrast) > 0.001 || abs(s.saturation) > 0.001 {
            // Kontrast wirkt in Gamma-Raum natürlicher als im linearen Arbeitsraum.
            let f = CIFilter.colorControls()
            f.inputImage = toGamma(img)
            f.contrast = Float(1 + s.contrast * 0.5)
            f.saturation = Float(1 + s.saturation)
            f.brightness = 0
            img = toLinear(f.outputImage ?? toGamma(img))
        }
        return img
    }

    // MARK: 6 – Vignette & Korn

    private func vignette(_ img: CIImage, amount: Double, rect: CGRect) -> CIImage {
        let f = CIFilter.vignetteEffect()
        f.inputImage = img
        f.center = CGPoint(x: rect.midX, y: rect.midY)
        f.radius = Float(hypot(rect.width, rect.height) * 0.5 * 0.85)
        f.intensity = Float(amount.clamped(0, 1))
        f.falloff = 0.55
        return (f.outputImage ?? img).cropped(to: rect)
    }

    private func grain(_ img: CIImage, _ s: AnamorphicSettings, rect: CGRect, seed: Int) -> CIImage {
        // Korngröße relativ zur Breite → Vorschau und Export sehen gleich aus
        let cell = max(1.0, (0.8 + s.grainSize.clamped(0, 1) * 1.6) * rect.width / 1920.0)

        guard var noise = CIFilter.randomGenerator().outputImage else { return img }
        // Pro Frame ein anderer Ausschnitt des Rauschens, sonst "klebt" das Korn.
        let ox = Double(abs(seed &* 7919) % 4096)
        let oy = Double(abs(seed &* 104729) % 4096)
        noise = noise
            .transformed(by: CGAffineTransform(translationX: ox, y: oy))
            .transformed(by: CGAffineTransform(scaleX: cell, y: cell))
            .cropped(to: rect)

        // Monochromes Rauschen um 0.5
        let amp = s.grain.clamped(0, 1) * 1.1
        let bias = 0.5 - 0.5 * amp
        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise
        mono.rVector = CIVector(x: 0.30 * amp, y: 0.59 * amp, z: 0.11 * amp, w: 0)
        mono.gVector = CIVector(x: 0.30 * amp, y: 0.59 * amp, z: 0.11 * amp, w: 0)
        mono.bVector = CIVector(x: 0.30 * amp, y: 0.59 * amp, z: 0.11 * amp, w: 0)
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mono.biasVector = CIVector(x: bias, y: bias, z: bias, w: 1)
        guard let grainLayer = mono.outputImage else { return img }

        let blend = CIFilter.overlayBlendMode()
        blend.inputImage = grainLayer
        blend.backgroundImage = toGamma(img)
        guard let mixed = blend.outputImage else { return img }
        return toLinear(mixed).cropped(to: rect)
    }

    // MARK: Export-Helfer

    enum PhotoFormat: String, CaseIterable, Identifiable {
        case jpeg, heic, png
        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
        var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    }

    func encode(_ image: CIImage, format: PhotoFormat) throws -> Data {
        let cs = Self.outputColorSpace
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        let data: Data?
        switch format {
        case .jpeg:
            data = context.jpegRepresentation(of: image, colorSpace: cs, options: [quality: 0.95])
        case .heic:
            data = context.heifRepresentation(of: image, format: .RGBA8, colorSpace: cs, options: [quality: 0.9])
        case .png:
            data = context.pngRepresentation(of: image, format: .RGBA8, colorSpace: cs, options: [:])
        }
        guard let data else { throw NSError(domain: "Anamorphic", code: 1, userInfo: [NSLocalizedDescriptionKey: "Das Bild konnte nicht kodiert werden."]) }
        return data
    }
}
