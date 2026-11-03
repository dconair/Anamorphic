import Foundation

/// Parametrisches Grading-Rezept. Arbeitet auf gamma-kodierten Werten (0…1, Rec.709-artig),
/// daraus wird beim Start eine echte 3D-LUT gebacken. So gibt es keine Binär-Assets und der
/// Look lässt sich als .cube exportieren.
struct LookRecipe: Sendable {
    var contrast: Float = 0.3            // 0 … 1, S-Kurve um die Mitte
    var saturation: Float = 1.0
    var shadowTint: (r: Float, g: Float, b: Float) = (0, 0, 0)
    var highlightTint: (r: Float, g: Float, b: Float) = (0, 0, 0)
    var fade: Float = 0.0                // angehobenes Schwarz
    var highlightRolloff: Float = 0.82   // ab hier werden Lichter weich geführt

    func apply(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        var c = [r, g, b]

        // Split-Toning gewichtet nach Luminanz
        let lum = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        let sw = 1 - Self.smoothstep(0.0, 0.55, lum)
        let hw = Self.smoothstep(0.45, 1.0, lum)
        c[0] += shadowTint.r * sw + highlightTint.r * hw
        c[1] += shadowTint.g * sw + highlightTint.g * hw
        c[2] += shadowTint.b * sw + highlightTint.b * hw

        // S-Kurve
        for i in 0..<3 {
            let x = min(max(c[i], 0), 1)
            let s = x * x * (3 - 2 * x)
            c[i] = x + (s - x) * contrast
        }

        // Sättigung relativ zur neuen Luminanz
        let l2 = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        for i in 0..<3 { c[i] = l2 + (c[i] - l2) * saturation }

        // Fade + weiche Lichter
        for i in 0..<3 {
            var v = c[i]
            if v > highlightRolloff {
                let span = 1 - highlightRolloff
                v = highlightRolloff + span * (1 - exp(-(v - highlightRolloff) / span))
            }
            v = fade + v * (1 - fade)
            c[i] = min(max(v, 0), 1)
        }
        return (c[0], c[1], c[2])
    }

    private static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

struct BuiltInLook: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let recipe: LookRecipe
}

enum LookLibrary {
    static let none = BuiltInLook(id: "none", title: "Kein Look", subtitle: "Unverändert", recipe: LookRecipe(contrast: 0, saturation: 1))

    static let all: [BuiltInLook] = [
        none,
        BuiltInLook(id: "cinema", title: "Cinema", subtitle: "Kühle Schatten, warme Hauttöne",
                    recipe: LookRecipe(contrast: 0.32, saturation: 1.04,
                                       shadowTint: (-0.025, 0.004, 0.035),
                                       highlightTint: (0.035, 0.012, -0.03),
                                       fade: 0.018)),
        BuiltInLook(id: "nightBlue", title: "Nachtblau", subtitle: "Kalte Nacht, gedämpfte Farben",
                    recipe: LookRecipe(contrast: 0.4, saturation: 0.88,
                                       shadowTint: (-0.035, 0.0, 0.06),
                                       highlightTint: (0.015, 0.012, 0.0),
                                       fade: 0.03)),
        BuiltInLook(id: "tungsten", title: "Tungsten 500", subtitle: "Warmes Kunstlicht-Negativ",
                    recipe: LookRecipe(contrast: 0.28, saturation: 1.1,
                                       shadowTint: (-0.015, 0.01, 0.03),
                                       highlightTint: (0.06, 0.022, -0.035),
                                       fade: 0.04)),
        BuiltInLook(id: "goldenHour", title: "Goldene Stunde", subtitle: "Weiche, warme Lichter",
                    recipe: LookRecipe(contrast: 0.22, saturation: 1.06,
                                       shadowTint: (0.008, 0.0, -0.01),
                                       highlightTint: (0.07, 0.03, -0.05),
                                       fade: 0.035)),
        BuiltInLook(id: "softFilm", title: "Soft Film", subtitle: "Flach, entsättigt, Eterna-artig",
                    recipe: LookRecipe(contrast: 0.14, saturation: 0.86,
                                       shadowTint: (0.0, 0.01, 0.014),
                                       highlightTint: (0.02, 0.012, 0.0),
                                       fade: 0.06)),
        BuiltInLook(id: "bleach", title: "Bleach Bypass", subtitle: "Hart, entsättigt, silbrig",
                    recipe: LookRecipe(contrast: 0.6, saturation: 0.55, fade: 0.012)),
        BuiltInLook(id: "mono", title: "Mono", subtitle: "Schwarzweiß mit Filmkontrast",
                    recipe: LookRecipe(contrast: 0.42, saturation: 0.0, fade: 0.025)),
    ]

    static func look(id: String) -> BuiltInLook? { all.first { $0.id == id } }

    // Thread-sicherer Cache: die Video-Pipeline ruft aus mehreren Threads ab.
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var storage: [String: CubeLUT] = [:]
    }
    private static let cache = Cache()

    static func lut(for id: String) -> CubeLUT? {
        guard id != "none", let look = look(id: id) else { return nil }
        cache.lock.lock(); defer { cache.lock.unlock() }
        if let hit = cache.storage[id] { return hit }
        let lut = CubeLUT.generate(title: look.title, size: 33) { r, g, b in look.recipe.apply(r, g, b) }
        cache.storage[id] = lut
        return lut
    }

    /// "custom" meint die vom Nutzer importierte LUT.
    static func resolve(id: String, custom: CubeLUT?) -> CubeLUT? {
        id == "custom" ? custom : lut(for: id)
    }

    /// Fünf Referenzfarben (Schatten, Mitte, Licht, Haut, Himmel) für die Vorschau-Leiste.
    static let swatchInputs: [(Float, Float, Float)] = [
        (0.07, 0.07, 0.08), (0.36, 0.34, 0.33), (0.82, 0.80, 0.76), (0.80, 0.58, 0.46), (0.34, 0.50, 0.76),
    ]
}
