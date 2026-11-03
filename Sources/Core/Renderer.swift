import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

/// Die komplette Bild-Pipeline (Foto-Export, Vorschau und jeder Video-Frame laufen hier durch).
///
/// Leitidee: ein echter Anamorphot staucht das Bild horizontal (Squeeze), das Objektiv und der Sensor
/// arbeiten in diesem gestauchten Raum, und erst beim Entzerren (Desqueeze) wird es wieder breit gezogen.
/// Alles, was Optik oder Sensor ausmacht, wird deshalb mitgestreckt: Unschärfescheiben, Glimmer, Randunschärfe,
/// Vignette und sogar das Korn werden horizontal länglich. Genau das emuliert `sensorDomain`: ein Effekt wird im
/// gestauchten Raum rund gerechnet und danach wieder auf die Breite gezogen. Das Motiv selbst behält seine
/// Proportionen, und das scharfe Originalbild bleibt als Basis erhalten (keine Auflösung geht verloren).
///
/// Reihenfolge – vom Glas zum Sensor zur Farbkorrektur:
///   1. Bokeh (Motiv bleibt scharf, Hintergrund bekommt ovale Scheiben)
///   2. Randunschärfe (wie bei echten Anamorphoten zum Rand weicher)
///   3. Laterale Farbsäume zum Rand
///   4. Streak-Flares + Halation – nur von kleinen, sehr hellen Lichtquellen des Originalbilds
///   5. Breitenstreckung mit Randbetonung, danach Zuschnitt auf das Zielformat
///   6. Farbe: Belichtung, Weißabgleich, Lichter/Tiefen, LUT, Kontrast/Sättigung
///   7. Ovale Vignette, längliches Korn
///   8. Untertitel
///
/// Alle Konstanten, die den Charakter bestimmen, stehen in `Tuning`.
final class AnamorphicRenderer: @unchecked Sendable {

    enum Tuning {
        /// Faktor Bokeh-Radius (relativ zur Bildbreite) bei Stärke = 1
        static let bokehRadiusPerWidth = 0.018
        /// Randunschärfe: Blur-Radius (relativ zur Bildbreite) bei Stärke = 1
        static let edgeBlurPerWidth = 0.004
        /// Lichtquellen werden auf diese Größe verkleinert (Performance, und der Streak wird dadurch länger)
        static let streakDownscale = 0.25
        /// Maximale Motion-Blur-Länge von Core Image (px im verkleinerten Bild)
        static let streakMaxRadius = 100.0
        /// Ausgleich, weil Motion-Blur mittelt: Verstärkung = streakGain × Länge
        static let streakGain = 0.10
        /// Streaks werden nie heller als dieser Wert (vor Intensität)
        static let streakClamp = 0.8
        /// Größte Lichtquelle, die noch streut (Anteil der Bildbreite); größere Flächen werden ignoriert
        static let maxSourceSizePerWidth = 0.012
        /// Chromatische Aberration: maximale Skalendifferenz R/B bei Stärke = 1
        static let aberrationMaxScale = 0.004
        /// Korn: Amplitude bei Stärke = 1
        static let grainAmplitude = 0.45
        /// Nachschärfen nach der Streckung (CISharpenLuminance)
        static let stretchSharpen = 0.35
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
        let original = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
        var img = original
        let inputExtent = img.extent

        // 1–4: Optik
        if s.bokehEnabled && s.bokehAmount > 0.01 {
            img = bokeh(img, s, subjectMask: subjectMask)
        }
        if s.edgeSoftness > 0.01 {
            img = edgeSoftness(img, s)
        }
        if s.aberration > 0.01 {
            img = chromaticAberration(img, amount: s.aberration * Tuning.aberrationMaxScale)
        }
        if s.flareEnabled || s.halation > 0.01 {
            img = flares(img, s, sourceImage: original)
        }

        // 5: Geometrie
        let geo = s.geometry(for: inputExtent.size)
        img = stretch(img, s)
        img = img.cropped(to: geo.crop)
            .transformed(by: CGAffineTransform(translationX: -geo.crop.minX, y: -geo.crop.minY))
        let outRect = CGRect(origin: .zero, size: geo.crop.size)

        // 6: Farbe
        img = grade(img, s, lut: lut)

        // 7: Film
        if s.vignette > 0.01 { img = vignette(img, amount: s.vignette, rect: outRect, squeeze: s.squeeze) }
        if s.grain > 0.01 { img = grain(img, s, rect: outRect, seed: frameSeed) }

        // 8: Untertitel liegen ganz oben (nach Grading und Korn), wie in der echten Postproduktion
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

    private func clampPositive(_ img: CIImage, maxValue: Double = 16) -> CIImage {
        let c = CIFilter.colorClamp()
        c.inputImage = img
        c.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        c.maxComponents = CIVector(x: maxValue, y: maxValue, z: maxValue, w: 1)
        return c.outputImage ?? img
    }

    private func gaussian(_ img: CIImage, radius: Double) -> CIImage {
        let ext = img.extent
        let f = CIFilter.gaussianBlur()
        f.inputImage = img.clampedToExtent()
        f.radius = Float(max(0.01, radius))
        return (f.outputImage ?? img).cropped(to: ext)
    }

    /// Wie stark Effekte horizontal gedehnt werden, damit das Endergebnis die Anamorphot-Ovalität `squeeze` hat.
    /// Die Breitenstreckung des fertigen Bildes trägt bereits dazu bei und wird angerechnet.
    private func ovalFactor(_ s: AnamorphicSettings) -> Double {
        max(1.0, s.squeeze / max(1.0, s.desqueeze))
    }

    /// Führt `op` im horizontal gestauchten Raum aus und streckt das Ergebnis danach wieder.
    /// So wird jede runde Operation (Unschärfe, Glimmer …) zur ovalen – wie bei einem Anamorphoten.
    private func sensorDomain(_ img: CIImage, factor e: Double, _ op: (CIImage) -> CIImage) -> CIImage {
        let ext = img.extent
        if e <= 1.001 { return op(img) }
        let squeezed = img.transformed(by: CGAffineTransform(scaleX: 1.0 / e, y: 1))
        return op(squeezed)
            .transformed(by: CGAffineTransform(scaleX: e, y: 1))
            .cropped(to: ext)
    }

    /// Per-Kanal-Schwelle (Schwelle in Anzeige-Helligkeit, Berechnung linear).
    private func highlights(of img: CIImage, threshold: Double, gain: Double) -> CIImage {
        let t = pow(threshold.clamped(0, 1), 2.2)
        let m = matrix(img,
                       r: [gain, 0, 0, 0], g: [0, gain, 0, 0], b: [0, 0, gain, 0],
                       bias: [-t * gain, -t * gain, -t * gain, 0])
        return clampPositive(m)
    }

    /// Schwelle auf der Luminanz; Ergebnis ist grau (alle Kanäle gleich).
    private func lumaHighlights(of img: CIImage, threshold: Double, gain: Double) -> CIImage {
        let t = pow(threshold.clamped(0, 1), 2.2)
        let l = [0.2126 * gain, 0.7152 * gain, 0.0722 * gain, 0]
        let m = matrix(img, r: l, g: l, b: l, bias: [-t * gain, -t * gain, -t * gain, 0])
        return clampPositive(m)
    }

    // MARK: 1 – Bokeh

    private func bokeh(_ img: CIImage, _ s: AnamorphicSettings, subjectMask: CIImage?) -> CIImage {
        let extent = img.extent
        let w = extent.width
        let e = ovalFactor(s)
        let radius = s.bokehAmount.clamped(0, 1) * Tuning.bokehRadiusPerWidth * w / e

        // Lichter vor dem Verwischen leicht anheben, damit helle Punkte als klare Scheiben erscheinen.
        var base = img
        if s.highlightBoost > 0.01 {
            let hl = highlights(of: img, threshold: 0.9, gain: 2.0)
            base = add(img, scaled(hl, by: s.highlightBoost.clamped(0, 1)))
        }

        let blurred = sensorDomain(base, factor: e) { squeezed in
            let f = CIFilter.bokehBlur()
            f.inputImage = squeezed.clampedToExtent()
            f.radius = Float(max(0.5, radius))
            f.ringAmount = 0.06
            f.ringSize = 0.1
            f.softness = 1.0
            return (f.outputImage ?? squeezed).cropped(to: squeezed.extent)
        }

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

    // MARK: 2 – Randunschärfe

    /// Echte Anamorphoten sind zum Rand weicher, vor allem in der Breite. Das gibt dem Bild Tiefe und nimmt
    /// die digitale Schärfe.
    private func edgeSoftness(_ img: CIImage, _ s: AnamorphicSettings) -> CIImage {
        let extent = img.extent
        let w = extent.width, h = extent.height
        let e = max(1.2, ovalFactor(s))
        let radius = s.edgeSoftness.clamped(0, 1) * Tuning.edgeBlurPerWidth * w / e

        let soft = sensorDomain(img, factor: e) { gaussian($0, radius: radius) }

        // Weiß = weich. Innerhalb der Ellipse bleibt das Bild scharf.
        let k = w / h
        let g = CIFilter.radialGradient()
        g.center = CGPoint(x: extent.midX / k, y: extent.midY)
        g.radius0 = Float(0.40 * h)
        g.radius1 = Float(0.85 * h)
        g.color0 = CIColor(red: 0, green: 0, blue: 0)
        g.color1 = CIColor(red: 1, green: 1, blue: 1)
        let mask = (g.outputImage ?? CIImage(color: .black))
            .transformed(by: CGAffineTransform(scaleX: k, y: 1))
            .cropped(to: extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = soft
        blend.backgroundImage = img
        blend.maskImage = mask
        return (blend.outputImage ?? img).cropped(to: extent)
    }

    // MARK: 3 – Chromatische Aberration

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

    // MARK: 4 – Flares & Halation

    /// Lichtquellen werden aus dem unveränderten Originalbild bestimmt (nicht aus dem schon verwischten Bild).
    /// Nur kleine, nahezu ausgebrannte Punkte zählen. Große helle Flächen (Fenster, weiße Wände) werden über
    /// ein Morphologie-"Top-Hat" (Bild minus Öffnung) ausgeschlossen – sie erzeugen weder Streaks noch Kantenlinien.
    private func flares(_ img: CIImage, _ s: AnamorphicSettings, sourceImage: CIImage) -> CIImage {
        let extent = img.extent
        let w = extent.width
        var out = img

        let ds = Tuning.streakDownscale
        let small = sourceImage.transformed(by: CGAffineTransform(scaleX: ds, y: ds))
        let smallExtent = small.extent
        let hl = lumaHighlights(of: small, threshold: s.flareThreshold, gain: 12.0)
        let sources = topHat(hl, extent: smallExtent, radius: max(2, w * ds * Tuning.maxSourceSizePerWidth / 2))

        if s.flareEnabled && s.flareIntensity > 0.01 && s.flareLength > 0.01 {
            let streak = streakLayer(from: sources, length: s.flareLength)
            let tint = s.flareTint.rgb
            let k = s.flareIntensity.clamped(0, 1) * 0.9
            let l: [Double] = [0.2126, 0.7152, 0.0722, 0]
            let tinted = matrix(upscale(streak, to: extent, by: ds),
                                r: l.map { $0 * tint.r * k },
                                g: l.map { $0 * tint.g * k },
                                b: l.map { $0 * tint.b * k })
            out = add(out, tinted)
        }

        if s.halation > 0.01 {
            // Warmer, roter Hof um Lichtquellen (Rückreflexion im Film/Glas), ebenfalls oval.
            let e = ovalFactor(s)
            let glow = sensorDomain(sources, factor: e) { gaussian($0, radius: w * ds * 0.012 / e) }
            let k = s.halation.clamped(0, 1) * 0.8
            let warm = matrix(upscale(glow, to: extent, by: ds),
                              r: [k * 1.0, 0, 0, 0],
                              g: [0, k * 0.38, 0, 0],
                              b: [0, 0, k * 0.16, 0])
            out = add(out, warm)
        }
        return out
    }

    private func upscale(_ img: CIImage, to extent: CGRect, by ds: Double) -> CIImage {
        img.transformed(by: CGAffineTransform(scaleX: 1 / ds, y: 1 / ds)).cropped(to: extent)
    }

    private func topHat(_ img: CIImage, extent: CGRect, radius: Double) -> CIImage {
        let r = Float(max(1, radius))
        let erode = CIFilter.morphologyMinimum()
        erode.inputImage = img.clampedToExtent()
        erode.radius = r
        let eroded = (erode.outputImage ?? img).cropped(to: extent)

        let dilate = CIFilter.morphologyMaximum()
        dilate.inputImage = eroded.clampedToExtent()
        dilate.radius = r
        let opened = (dilate.outputImage ?? eroded).cropped(to: extent)

        // img − opened, negative Werte abschneiden
        return clampPositive(add(img, scaled(opened, by: -1)))
    }

    private func streakLayer(from sources: CIImage, length: Double) -> CIImage {
        let ext = sources.extent

        func pass(_ radius: Double, weight: Double) -> CIImage {
            let f = CIFilter.motionBlur()
            f.inputImage = sources.clampedToExtent()
            f.radius = Float(max(1, radius))
            f.angle = 0
            let blurred = (f.outputImage ?? sources).cropped(to: ext)
            // Motion-Blur mittelt → Energie verteilt sich über die Länge. Die Verstärkung gleicht das aus.
            return scaled(blurred, by: Tuning.streakGain * radius * weight)
        }

        let rLong = Tuning.streakMaxRadius * length.clamped(0.05, 1)
        let combined = add(pass(rLong, weight: 0.7), pass(rLong * 0.35, weight: 0.5))
        return clampPositive(combined, maxValue: Tuning.streakClamp)
    }

    // MARK: 5 – Breitenstreckung

    /// Streckt das Bild in der Breite, in der Mitte weniger als am Rand (siehe `Stretch`).
    /// Jeder Streifen wird einzeln skaliert und auf ganzzahlige Pixelgrenzen gesetzt – ohne Nähte.
    private func stretch(_ img: CIImage, _ s: AnamorphicSettings) -> CIImage {
        if Stretch.isIdentity(desqueeze: s.desqueeze, edge: s.edgeStretch) { return img }
        let ext = img.extent
        let width = Int(ext.width.rounded())
        let height = ext.height
        let b = Stretch.boundaries(width: width, desqueeze: s.desqueeze, edge: s.edgeStretch)
        let base = img.clampedToExtent()
        let margin = 3                       // Rand für den Lanczos-Filter, damit an den Streifennähten nichts fehlt

        var result: CIImage?
        for i in 0..<Stretch.strips {
            let sx = b.src[i], ex = b.src[i + 1]
            let dx = b.dst[i], ed = b.dst[i + 1]
            guard ex > sx, ed > dx else { continue }
            let factor = CGFloat(ed - dx) / CGFloat(ex - sx)
            // Quellstreifen samt Rand → nach links an den Nullpunkt → Lanczos nur in der Breite → an Zielposition
            let srcRect = CGRect(x: CGFloat(sx - margin), y: 0, width: CGFloat(ex - sx + 2 * margin), height: height)
            let local = base.cropped(to: srcRect)
                .transformed(by: CGAffineTransform(translationX: CGFloat(-(sx - margin)), y: 0))
            let resized: CIImage
            if abs(factor - 1) < 0.0005 {
                resized = local
            } else {
                let f = CIFilter.lanczosScaleTransform()
                f.inputImage = local
                f.scale = 1
                f.aspectRatio = Float(factor)
                resized = f.outputImage ?? local.transformed(by: CGAffineTransform(scaleX: factor, y: 1))
            }
            let piece = resized
                .transformed(by: CGAffineTransform(translationX: CGFloat(dx) - CGFloat(margin) * factor, y: 0))
                .cropped(to: CGRect(x: CGFloat(dx), y: 0, width: CGFloat(ed - dx), height: height))
            result = result.map { piece.composited(over: $0) } ?? piece
        }
        guard var out = result else { return img }
        // Das Neuberechnen nimmt etwas Schärfe; ein dezentes Nachschärfen gleicht das aus.
        let sharp = CIFilter.sharpenLuminance()
        sharp.inputImage = out
        sharp.sharpness = Float(Tuning.stretchSharpen)
        sharp.radius = Float(max(1.0, ext.width * 0.0006))
        out = (sharp.outputImage ?? out).cropped(to: out.extent)
        return out
    }

    // MARK: 6 – Farbe

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

    // MARK: 7 – Vignette & Korn

    /// Ovale Vignette: eine Ellipse im Bildformat, im Anamorphot-Raum rund gerechnet.
    private func vignette(_ img: CIImage, amount: Double, rect: CGRect, squeeze: Double) -> CIImage {
        let k = rect.width / rect.height
        let g = CIFilter.radialGradient()
        g.center = CGPoint(x: rect.midX / k, y: rect.midY)
        g.radius0 = Float(0.40 * rect.height)
        g.radius1 = Float(0.85 * rect.height)
        let dark = 1 - 0.70 * amount.clamped(0, 1)
        g.color0 = CIColor(red: 1, green: 1, blue: 1)
        g.color1 = CIColor(red: dark, green: dark, blue: dark)
        guard let grad = g.outputImage else { return img }
        let mask = grad.transformed(by: CGAffineTransform(scaleX: k, y: 1)).cropped(to: rect)

        let mul = CIFilter.multiplyCompositing()
        mul.inputImage = mask
        mul.backgroundImage = img
        return (mul.outputImage ?? img).cropped(to: rect)
    }

    /// Korn entsteht auf dem Sensor, also im gestauchten Raum, und wird beim Entzerren mitgestreckt:
    /// echte Anamorphot-Aufnahmen haben deshalb horizontal längliches Korn. Das emulieren wir mit
    /// Zellen, die um den Anamorphot-Faktor breiter als hoch sind.
    private func grain(_ img: CIImage, _ s: AnamorphicSettings, rect: CGRect, seed: Int) -> CIImage {
        // Korngröße relativ zur Breite → Vorschau und Export sehen gleich aus
        let cell = max(1.0, (0.8 + s.grainSize.clamped(0, 1) * 1.6) * rect.width / 1920.0)
        let elongation = max(1.0, s.squeeze)

        guard var noise = CIFilter.randomGenerator().outputImage else { return img }
        // Pro Frame ein anderer Ausschnitt des Rauschens, sonst "klebt" das Korn.
        let ox = Double(abs(seed &* 7919) % 4096)
        let oy = Double(abs(seed &* 104729) % 4096)
        noise = noise
            .transformed(by: CGAffineTransform(translationX: ox, y: oy))
            .transformed(by: CGAffineTransform(scaleX: cell * elongation, y: cell))
            .cropped(to: rect)
        // Der Generator liefert Alpha-Zufallswerte. Alpha wird erst auf 1 gesetzt (ohne die Farbwerte
        // zu ändern), sonst teilt die Matrix durch kleine Alpha-Werte und es entstehen weiße Funken.
        noise = noise.settingAlphaOne(in: rect)

        // Monochromes Rauschen (nur Rotkanal) um 0.5, sehr dezent
        let amp = s.grain.clamped(0, 1) * Tuning.grainAmplitude
        let bias = 0.5 - 0.5 * amp
        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise
        mono.rVector = CIVector(x: amp, y: 0, z: 0, w: 0)
        mono.gVector = CIVector(x: amp, y: 0, z: 0, w: 0)
        mono.bVector = CIVector(x: amp, y: 0, z: 0, w: 0)
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
