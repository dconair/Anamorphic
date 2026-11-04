import XCTest
import CoreImage
import CoreImage.CIFilterBuiltins
@testable import AnamorphicCore

final class CubeLUTTests: XCTestCase {
    func testParsesIdentityLUT() throws {
        let text = """
        # kommentar
        TITLE "Test"
        LUT_3D_SIZE 2
        0 0 0
        1 0 0
        0 1 0
        1 1 0
        0 0 1
        1 0 1
        0 1 1
        1 1 1
        """
        let lut = try CubeLUT.parse(text)
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.title, "Test")
        XCTAssertEqual(lut.rgb.count, 24)
        XCTAssertEqual(lut.cubeData.count, 8 * 4 * MemoryLayout<Float>.size)
    }

    func testRejects1DAndBrokenFiles() {
        XCTAssertThrowsError(try CubeLUT.parse("LUT_1D_SIZE 16\n0 0 0")) {
            XCTAssertEqual($0 as? CubeLUTError, .unsupported1D)
        }
        XCTAssertThrowsError(try CubeLUT.parse("0 0 0")) {
            XCTAssertEqual($0 as? CubeLUTError, .missingSize)
        }
        XCTAssertThrowsError(try CubeLUT.parse("LUT_3D_SIZE 2\n0 0 0\n1 1 1"))
    }

    func testRoundTrip() throws {
        let original = LookLibrary.lut(for: "cinema")!
        let parsed = try CubeLUT.parse(original.cubeString())
        XCTAssertEqual(parsed.size, original.size)
        XCTAssertEqual(parsed.rgb.count, original.rgb.count)
        for (a, b) in zip(parsed.rgb, original.rgb) { XCTAssertEqual(a, b, accuracy: 0.0001) }
    }

    func testBuiltInLooksStayInRange() {
        for look in LookLibrary.all {
            guard let lut = LookLibrary.lut(for: look.id) else { continue }
            XCTAssertTrue(lut.rgb.allSatisfy { $0 >= 0 && $0 <= 1 }, look.id)
        }
    }
}

final class GeometryTests: XCTestCase {
    func testScopeCropFrom16x9() {
        var s = AnamorphicSettings()   // 2.39
        s.desqueeze = 1.0
        s.edgeStretch = 0
        s.expandEnabled = false
        let g = s.geometry(for: CGSize(width: 3840, height: 2160))
        XCTAssertEqual(g.crop.width, 3840)
        XCTAssertEqual(g.crop.height, 1606)
        XCTAssertEqual(g.crop.width.truncatingRemainder(dividingBy: 2), 0)
        XCTAssertEqual(g.crop.height.truncatingRemainder(dividingBy: 2), 0)
        XCTAssertEqual(g.crop.width / g.crop.height, 2.39, accuracy: 0.01)
    }

    func testPortraitSourceIsCroppedNotStretched() {
        var s = AnamorphicSettings()
        s.desqueeze = 1.0
        s.edgeStretch = 0
        s.expandEnabled = false
        let g = s.geometry(for: CGSize(width: 1080, height: 1920))
        XCTAssertEqual(g.crop.width, 1080)
        XCTAssertLessThan(g.crop.height, 1920)
    }

    func testOriginalKeepsFullFrame() {
        var s = AnamorphicSettings()
        s.aspect = .original
        s.desqueeze = 1.0
        s.edgeStretch = 0
        s.expandEnabled = false
        let g = s.geometry(for: CGSize(width: 4032, height: 3024))
        XCTAssertEqual(g.crop.size, CGSize(width: 4032, height: 3024))
    }

    func testDesqueezeWidensBefore() {
        var s = AnamorphicSettings()
        s.desqueeze = 1.33
        s.edgeStretch = 0
        s.expandEnabled = false
        s.aspect = .original
        let g = s.geometry(for: CGSize(width: 3000, height: 2250))   // 4:3 → ~16:9
        XCTAssertEqual(g.crop.width / g.crop.height, 16.0 / 9.0, accuracy: 0.01)
    }

    func testDefaultKeepsProportionsAlmostUntouched() {
        var s = AnamorphicSettings()
        s.expandEnabled = false
        let g = s.geometry(for: CGSize(width: 4000, height: 3000))
        // Standard: Mitte unverändert, nur der Rand etwas breiter (insgesamt < +6 %)
        XCTAssertGreaterThanOrEqual(g.stretchedSize.width, 4000)
        XCTAssertLessThan(g.stretchedSize.width, 4000 * 1.06)
        XCTAssertEqual(g.stretchedSize.height, 3000)
        XCTAssertEqual(g.crop.width / g.crop.height, 2.39, accuracy: 0.02)
    }

    func testStretchCenterEqualsDesqueezeAndEdgeIsLarger() {
        for (d, e) in [(1.0, 0.5), (1.33, 0.0), (1.5, 1.0)] {
            let f = Stretch.factors(desqueeze: d, edge: e)
            XCTAssertEqual(f.center, d, accuracy: 1e-9)
            XCTAssertEqual(f.edge, d * (1 + Stretch.maxEdgeGain * e), accuracy: 1e-9)
            let w = 4000
            let out = Double(Stretch.outputWidth(width: w, desqueeze: d, edge: e)) / Double(w)
            XCTAssertGreaterThanOrEqual(out, d - 0.01)
            XCTAssertLessThanOrEqual(out, f.edge + 0.01)
        }
    }

    func testExpansionWidensImageButKeepsCenter() {
        let w = 4000
        let out = Double(Stretch.outputWidth(width: w, desqueeze: 1, edge: 0, expansion: 1.2)) / Double(w)
        XCTAssertEqual(out, 1.2, accuracy: 0.01)
        let b = Stretch.boundaries(width: w, desqueeze: 1, edge: 0, expansion: 1.2)
        let n = Stretch.strips
        let mid = Double(b.dst[n / 2 + 1] - b.dst[n / 2]) / Double(b.src[n / 2 + 1] - b.src[n / 2])
        let edge = Double(b.dst[1] - b.dst[0]) / Double(b.src[1] - b.src[0])
        XCTAssertEqual(mid, 1.0, accuracy: 0.001)       // Mitte unverändert
        XCTAssertGreaterThan(edge, 1.5)                 // Rand deutlich gedehnt
        XCTAssertLessThan(edge, 2.6)
    }

    func testExpansionOnByDefault() {
        let s = AnamorphicSettings()
        let g = s.geometry(for: CGSize(width: 4000, height: 3000))
        XCTAssertEqual(g.stretchedSize.width / 4000, 1.2, accuracy: 0.04)
    }

    func testStretchEdgesStretchMoreThanCenter() {
        let b = Stretch.boundaries(width: 4000, desqueeze: 1.3, edge: 0.8)
        let n = Stretch.strips
        let first = Double(b.dst[1] - b.dst[0]) / Double(b.src[1] - b.src[0])
        let mid = Double(b.dst[n / 2 + 1] - b.dst[n / 2]) / Double(b.src[n / 2 + 1] - b.src[n / 2])
        XCTAssertGreaterThan(first, mid)
        XCTAssertEqual(b.dst.sorted(), b.dst)
    }

    func testVerticalOffsetStaysInsideImage() {
        var s = AnamorphicSettings()
        for off in [-1.0, 0.0, 1.0] {
            s.verticalOffset = off
            let g = s.geometry(for: CGSize(width: 4032, height: 3024))
            XCTAssertGreaterThanOrEqual(g.crop.minY, 0)
            XCTAssertLessThanOrEqual(g.crop.maxY, 3024)
        }
    }

    func testSettingsCodableRoundTrip() throws {
        var s = AnamorphicSettings()
        s.flareTint = .amber
        s.lookID = "tungsten"
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(AnamorphicSettings.self, from: data), s)
    }
}

final class RendererSmokeTests: XCTestCase {
    private func testImage(width: Int = 960, height: Int = 540) -> CIImage {
        // Dunkler Verlauf mit zwei hellen "Lichtquellen"
        let base = CIFilter.linearGradient()
        base.point0 = CGPoint(x: 0, y: 0)
        base.point1 = CGPoint(x: 0, y: CGFloat(height))
        base.color0 = CIColor(red: 0.05, green: 0.06, blue: 0.1)
        base.color1 = CIColor(red: 0.3, green: 0.3, blue: 0.35)
        var img = base.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        for (x, y) in [(300, 300), (700, 380)] {
            let g = CIFilter.radialGradient()
            g.center = CGPoint(x: x, y: y)
            g.radius0 = 6
            g.radius1 = 8
            g.color0 = CIColor(red: 1, green: 1, blue: 1)
            g.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            img = g.outputImage!.cropped(to: img.extent).composited(over: img)
        }
        return img
    }

    func testDefaultPipelineProducesScopeFrame() {
        let renderer = AnamorphicRenderer()
        let s = AnamorphicSettings()
        let src = testImage()
        let out = renderer.process(src, settings: s, lut: LookLibrary.lut(for: s.lookID), subjectMask: nil, frameSeed: 3)
        XCTAssertEqual(out.extent.origin, .zero)
        XCTAssertEqual(out.extent.width / out.extent.height, 2.39, accuracy: 0.02)
        let cg = renderer.context.createCGImage(out, from: out.extent)
        XCTAssertNotNil(cg)
    }

    func testEveryPresetRenders() {
        let renderer = AnamorphicRenderer()
        let src = testImage()
        for preset in StylePreset.allCases {
            let s = preset.settings
            let out = renderer.process(src, settings: s, lut: LookLibrary.lut(for: s.lookID), subjectMask: nil, frameSeed: 1)
            XCTAssertNotNil(renderer.context.createCGImage(out, from: out.extent), preset.rawValue)
        }
    }

    /// Schreibt Beispielbilder (nur wenn SAMPLE_DIR gesetzt ist; in CI als Artefakt zur Sichtprüfung).
    func testWriteSamples() throws {
        guard let dir = ProcessInfo.processInfo.environment["SAMPLE_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let renderer = AnamorphicRenderer()
        let src = testImage(width: 1920, height: 1080)
        func write(_ name: String, _ s: AnamorphicSettings) throws {
            let out = renderer.process(src, settings: s, lut: LookLibrary.lut(for: s.lookID), subjectMask: nil, frameSeed: 1)
            let data = try renderer.encode(out, format: .png)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        var flat = AnamorphicSettings(); flat.aspect = .original
        flat.lookID = "none"; flat.desqueeze = 1; flat.edgeStretch = 0; flat.expandEnabled = false
        flat.bokehEnabled = false; flat.flareEnabled = false; flat.halation = 0
        flat.aberration = 0; flat.edgeSoftness = 0; flat.grain = 0; flat.vignette = 0
        try write("00-original", flat)
        for preset in StylePreset.allCases { try write("preset-\(preset.rawValue)", preset.settings) }

        // Detail-Szene (Schachbrett + Kreis): zeigt Schärfe, Streckung und Randverlauf
        let cb = CIFilter.checkerboardGenerator()
        cb.center = .zero
        cb.width = 40
        cb.color0 = CIColor(red: 0.85, green: 0.82, blue: 0.75)
        cb.color1 = CIColor(red: 0.2, green: 0.22, blue: 0.25)
        cb.sharpness = 1
        let detail = cb.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let circle = CIFilter.radialGradient()
        circle.center = CGPoint(x: 960, y: 540)
        circle.radius0 = 180
        circle.radius1 = 182
        circle.color0 = CIColor(red: 0.9, green: 0.3, blue: 0.2)
        circle.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        let scene = circle.outputImage!.cropped(to: detail.extent).composited(over: detail)
        func writeDetail(_ name: String, _ s: AnamorphicSettings) throws {
            let out = renderer.process(scene, settings: s, lut: LookLibrary.lut(for: s.lookID), subjectMask: nil, frameSeed: 1)
            try renderer.encode(out, format: .png).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        try writeDetail("detail-original", flat)
        try writeDetail("detail-geometrie", StylePreset.clean.settings)
        try writeDetail("detail-natural", StylePreset.natural.settings)
    }

    func testFlareBrightensAroundLights() {
        let renderer = AnamorphicRenderer()
        var off = StylePreset.clean.settings
        off.aspect = .original
        off.desqueeze = 1
        off.edgeStretch = 0
        off.expandEnabled = false
        var on = off
        on.flareEnabled = true
        on.flareIntensity = 1
        on.flareThreshold = 0.9
        let src = testImage()
        let a = renderer.process(src, settings: off, lut: nil, subjectMask: nil, frameSeed: 0)
        let b = renderer.process(src, settings: on, lut: nil, subjectMask: nil, frameSeed: 0)

        func pixel(_ img: CIImage, x: Int, y: Int) -> Float {
            var px = [Float](repeating: 0, count: 4)
            renderer.context.render(img, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                                    format: .RGBAf, colorSpace: nil)
            return px[2]   // Blaukanal
        }
        // 80 px neben der Lichtquelle, auf gleicher Höhe: Streak muss heller sein als ohne Flare.
        XCTAssertGreaterThan(pixel(b, x: 380, y: 300), pixel(a, x: 380, y: 300))
    }
}


final class AnalysisTests: XCTestCase {
    func testNightSceneSuggestsNightPreset() {
        var a = ImageAnalysis()
        a.meanLuma = 0.12
        a.darkFraction = 0.7
        a.lightSourceCount = 5
        let best = ImageAnalyzer.suggestions(for: a).first
        XCTAssertEqual(best?.preset, .nightCity)
    }

    func testWarmBrightSceneSuggestsGoldenHour() {
        var a = ImageAnalysis()
        a.meanLuma = 0.62
        a.warmth = 0.2
        a.saturation = 0.5
        a.contrast = 0.7
        let best = ImageAnalyzer.suggestions(for: a).first
        XCTAssertEqual(best?.preset, .goldenHour)
    }

    func testTuningDisablesFlaresWithoutLightSources() {
        var a = ImageAnalysis()
        a.lightSourceCount = 0
        let s = ImageAnalyzer.tuned(StylePreset.nightCity.settings, for: a)
        XCTAssertFalse(s.flareEnabled)
    }

    func testTuningProtectsFaces() {
        var a = ImageAnalysis()
        a.faceCount = 1
        var base = AnamorphicSettings()
        base.desqueeze = 1.5
        base.edgeStretch = 0
        let s = ImageAnalyzer.tuned(base, for: a)
        XCTAssertLessThanOrEqual(s.desqueeze, 1.1)
        XCTAssertLessThanOrEqual(s.edgeStretch, 0.4)
    }

    func testSubtitleTimingFadesAndHides() {
        var s = AnamorphicSettings()
        s.subtitleStart = 2
        s.subtitleEnd = 5
        XCTAssertEqual(s.subtitleOpacity(at: nil), 1)          // Foto
        XCTAssertEqual(s.subtitleOpacity(at: 1.0), 0)           // davor
        XCTAssertEqual(s.subtitleOpacity(at: 3.0), 1)           // sichtbar
        XCTAssertEqual(s.subtitleOpacity(at: 5.5), 0)           // danach
        XCTAssertGreaterThan(s.subtitleOpacity(at: 2.05), 0)    // Einblenden
        XCTAssertLessThan(s.subtitleOpacity(at: 2.05), 1)
        s.subtitleEnd = 0                                       // bis zum Ende
        XCTAssertEqual(s.subtitleOpacity(at: 100), 1)
    }

    func testBlendInterpolatesNumbers() {
        var a = AnamorphicSettings(); a.grain = 0
        var b = AnamorphicSettings(); b.grain = 1
        XCTAssertEqual(AnamorphicSettings.blend(a, b, t: 0.25).grain, 0.25, accuracy: 1e-9)
    }
}
