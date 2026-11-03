import Foundation
import CoreGraphics
import CoreText
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Auswahl-Typen

enum SubtitleStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Weiß mit weichem Schatten – wie Streaming-Untertitel
    case cinema
    /// Gelb mit dunkler Kontur – klassischer Kino-/DVD-Untertitel
    case classic
    /// Schwarzer, leicht verwaschener Kleinbuchstaben-Text auf Brat-Grün
    case brat

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cinema: return "Kino"
        case .classic: return "Klassisch"
        case .brat: return "Brat"
        }
    }

    /// Passende Standardschrift zum Stil
    var defaultFont: SubtitleFont {
        switch self {
        case .cinema: return .sans
        case .classic: return .serif
        case .brat: return .narrow
        }
    }
}

enum SubtitleFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case sans, serif, condensed, typewriter, didot, narrow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sans: return "Helvetica"
        case .serif: return "Georgia"
        case .condensed: return "Avenir Condensed"
        case .typewriter: return "Courier"
        case .didot: return "Didot"
        case .narrow: return "Arial Narrow"
        }
    }

    /// PostScript-Namen in Prioritätsreihenfolge. Alle Schriften liegen auf iOS und macOS vor;
    /// "Arial Narrow" fehlt auf manchen iOS-Versionen, dann greift Arial.
    var postScriptNames: [String] {
        switch self {
        case .sans: return ["HelveticaNeue-Medium", "Helvetica"]
        case .serif: return ["Georgia", "TimesNewRomanPSMT"]
        case .condensed: return ["AvenirNextCondensed-DemiBold", "AvenirNextCondensed-Medium"]
        case .typewriter: return ["CourierNewPS-BoldMT", "Courier-Bold"]
        case .didot: return ["Didot", "Didot-Bold"]
        case .narrow: return ["ArialNarrow", "ArialNarrow-Bold", "ArialMT", "Helvetica"]
        }
    }

    func ctFont(size: CGFloat) -> CTFont {
        for name in postScriptNames {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            let resolved = CTFontCopyPostScriptName(font) as String
            if resolved.caseInsensitiveCompare(name) == .orderedSame { return font }
        }
        return CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }
}

// MARK: - Rendering

/// Zeichnet Untertitel mit CoreText in eine transparente Ebene in Ausgabegröße.
/// Die Ebene wird gecacht, weil sie sich innerhalb eines Videos nicht ändert.
enum SubtitleRenderer {
    private struct Key: Equatable {
        let text: String
        let style: SubtitleStyle
        let font: SubtitleFont
        let size: Double
        let position: Double
        let width: Int
        let height: Int
    }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var key: Key?
        var image: CIImage?
    }
    private static let cache = Cache()

    static func layer(for s: AnamorphicSettings, size: CGSize) -> CIImage? {
        let text = s.subtitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.subtitleEnabled, !text.isEmpty, size.width >= 2, size.height >= 2 else { return nil }

        let key = Key(text: text, style: s.subtitleStyle, font: s.subtitleFont, size: s.subtitleSize,
                      position: s.subtitlePosition, width: Int(size.width), height: Int(size.height))
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if cache.key == key, let hit = cache.image { return hit }

        let image = draw(key)
        cache.key = key
        cache.image = image
        return image
    }

    private static func draw(_ k: Key) -> CIImage? {
        let w = k.width, h = k.height
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))

        // Schriftgröße relativ zur Bildhöhe → Vorschau und Export stimmen überein
        let styleFactor: CGFloat = k.style == .brat ? 1.25 : 1.0
        let fontSize = CGFloat(h) * 0.050 * (0.65 + CGFloat(k.size) * 1.0) * styleFactor
        let font = k.font.ctFont(size: fontSize)
        let display = k.style == .brat ? k.text.lowercased() : k.text

        var alignment = CTTextAlignment.center
        let paragraph: CTParagraphStyle = withUnsafeMutablePointer(to: &alignment) { ptr in
            var setting = CTParagraphStyleSetting(spec: .alignment,
                                                  valueSize: MemoryLayout<CTTextAlignment>.size,
                                                  value: UnsafeRawPointer(ptr))
            return CTParagraphStyleCreate(&setting, 1)
        }

        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTParagraphStyleAttributeName: paragraph,
            kCTForegroundColorFromContextAttributeName: true,
        ]
        guard let attributed = CFAttributedStringCreate(nil, display as CFString, attributes as CFDictionary) else { return nil }
        let setter = CTFramesetterCreateWithAttributedString(attributed)

        let maxWidth = CGFloat(w) * (k.style == .brat ? 0.72 : 0.78)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                               CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
        let textW = min(maxWidth, ceil(fit.width) + 2)
        let textH = ceil(fit.height) + 2
        let bottom = CGFloat(h) * CGFloat(k.position)

        // Textblock in der Mitte, Unterkante bei `bottom`
        let textRect = CGRect(x: (CGFloat(w) - maxWidth) / 2, y: bottom, width: maxWidth, height: textH)

        switch k.style {
        case .cinema:
            ctx.setShadow(offset: CGSize(width: 0, height: -fontSize * 0.05), blur: fontSize * 0.22,
                          color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.9))
            ctx.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1))
            ctx.setTextDrawingMode(.fill)

        case .classic:
            ctx.setLineJoin(.round)
            ctx.setLineWidth(max(1, fontSize * 0.07))
            ctx.setStrokeColor(CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1))
            ctx.setFillColor(CGColor(red: 1.0, green: 0.86, blue: 0.22, alpha: 1))
            ctx.setTextDrawingMode(.fillStroke)

        case .brat:
            // #8ACE00 – das Brat-Grün
            let pad = fontSize * 0.28
            let box = CGRect(x: (CGFloat(w) - textW) / 2, y: bottom, width: textW, height: textH).insetBy(dx: -pad, dy: -pad * 0.6)
            ctx.setFillColor(CGColor(red: 0.541, green: 0.808, blue: 0.0, alpha: 1))
            ctx.fill(box)
            ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1))
            ctx.setTextDrawingMode(.fill)
        }

        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, ctx)

        guard let cg = ctx.makeImage() else { return nil }
        var image = CIImage(cgImage: cg)

        if k.style == .brat {
            // Der typische leicht unscharfe, "zu stark komprimierte" Brat-Text
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = image.clampedToExtent()
            blur.radius = Float(max(0.8, Double(h) * 0.0016))
            image = (blur.outputImage ?? image).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return image
    }
}
