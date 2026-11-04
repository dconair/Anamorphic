import Foundation
import CoreGraphics

// MARK: - Auswahl-Typen

/// Ziel-Bildformat. Der Zuschnitt passiert immer mittig (plus vertikalem Versatz),
/// nie durch Verzerren des Bildes.
enum AspectTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case scope239, scope235, wide200, flat185, original

    var id: String { rawValue }

    var ratio: Double? {
        switch self {
        case .scope239: return 2.39
        case .scope235: return 2.35
        case .wide200: return 2.0
        case .flat185: return 1.85
        case .original: return nil
        }
    }

    var title: String {
        switch self {
        case .scope239: return "2.39"
        case .scope235: return "2.35"
        case .wide200: return "2.00"
        case .flat185: return "1.85"
        case .original: return "Orig."
        }
    }
}

enum FocusMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case subject, ellipse
    var id: String { rawValue }
    var title: String { self == .subject ? "Motiv" : "Ellipse" }
}

enum FlareTint: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue, amber, white, magenta
    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return "Blau"
        case .amber: return "Bernstein"
        case .white: return "Neutral"
        case .magenta: return "Magenta"
        }
    }

    /// Linearer RGB-Multiplikator des Streaks (auf Luminanz angewendet).
    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .blue: return (0.30, 0.55, 1.00)
        case .amber: return (1.00, 0.62, 0.25)
        case .white: return (1.00, 0.97, 0.92)
        case .magenta: return (0.85, 0.35, 0.95)
        }
    }
}

/// In welchem Farbraum eine .cube-LUT gemeint ist. Core Image konvertiert vor dem
/// LUT-Lookup vom Arbeitsfarbraum in diesen Raum.
enum LUTSpace: String, Codable, CaseIterable, Identifiable, Sendable {
    case rec709, srgb, displayP3
    var id: String { rawValue }

    var title: String {
        switch self {
        case .rec709: return "Rec.709"
        case .srgb: return "sRGB"
        case .displayP3: return "Display P3"
        }
    }

    var cgColorSpace: CGColorSpace {
        switch self {
        case .rec709: return CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
        case .srgb: return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .displayP3: return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        }
    }
}

// MARK: - Einstellungen

/// Alle vom Nutzer einstellbaren Parameter. Alle Pixelgrößen werden relativ zur
/// Bildbreite berechnet, damit Vorschau (verkleinert) und Export (voll) gleich aussehen.
struct AnamorphicSettings: Codable, Equatable, Sendable {
    // Bildformat
    var aspect: AspectTarget = .scope239
    var verticalOffset: Double = 0          // -1 ... 1  (positiv = Ausschnitt nach oben)
    var desqueeze: Double = 1.0             // 1.0 ... 1.8  mittlere Breitenstreckung des fertigen Bildes
    var expandEnabled = true                // Bildwinkel erweitern: Randzonen werden weiter gedehnt, die Mitte bleibt
    var expansion = 1.12                    // 1.0 ... 1.5  Faktor, um den das Bild insgesamt breiter wird (Bildwinkel)
    var edgeStretch = 0.5                   // 0 ... 1      wie viel stärker der Rand gestreckt wird als die Mitte
    var squeeze = 1.5                       // 1.0 ... 2.0  Anamorphot-Faktor: Bokeh, Korn, Glimmer werden so oval

    // Bokeh
    var bokehEnabled = true
    var bokehAmount = 0.12                  // 0 ... 1
    var highlightBoost = 0.3                // 0 ... 1   Lichter werden zu Scheiben
    var focusMode: FocusMode = .subject
    var focusX = 0.5                        // 0 ... 1 (Ellipse)
    var focusY = 0.55
    var focusSize = 0.42                    // 0.1 ... 1
    var focusFeather = 0.5                  // 0 ... 1

    // Flares
    var flareEnabled = true
    var flareThreshold = 0.97               // 0.8 ... 1  (Anzeige-Helligkeit ab der Lichter streuen)
    var flareLength = 0.5                   // 0 ... 1
    var flareIntensity = 0.3                // 0 ... 1
    var flareTint: FlareTint = .blue
    var halation = 0.15                     // 0 ... 1  warmer Glimmer um Lichter

    // Optik
    var aberration = 0.15                   // 0 ... 1  laterale Farbsäume zum Rand
    var edgeSoftness = 0.08                 // 0 ... 1  Randunschärfe wie bei echten Anamorphoten

    // Look / Farbe
    var lookID = "cinema"
    var lookIntensity = 0.8                 // 0 ... 1
    var lutSpace: LUTSpace = .rec709
    var exposure = 0.0                      // -2 ... 2 EV
    var warmth = 0.0                        // -1 ... 1
    var tint = 0.0                          // -1 ... 1
    var highlights = 0.0                    // -1 ... 1
    var shadows = 0.0                       // -1 ... 1
    var contrast = 0.0                      // -1 ... 1
    var saturation = 0.0                    // -1 ... 1

    // Untertitel
    var subtitleEnabled = false
    var subtitleText = ""
    var subtitleStyle: SubtitleStyle = .cinema
    var subtitleFont: SubtitleFont = .sans
    var subtitleSize = 0.45                 // 0 ... 1
    var subtitleStart = 0.0                 // Sekunden; erscheint ab hier (nur Video)
    var subtitleEnd = 0.0                   // Sekunden; 0 = bis zum Ende des Videos
    var subtitlePosition = 0.09             // Abstand der Unterkante, Anteil der Bildhöhe (0 ... 0.4)

    // Film
    var grain = 0.15                        // 0 ... 1
    var grainSize = 0.4                     // 0 ... 1
    var vignette = 0.25                     // 0 ... 1
}

extension AnamorphicSettings {
    /// Erweiterungsfaktor, der tatsächlich angewendet wird.
    var effectiveExpansion: Double { expandEnabled ? expansion.clamped(1, 1.6) : 1 }

    /// Deckkraft des Untertitels zum Zeitpunkt `t` (Sekunden). `nil` = Foto: immer sichtbar.
    /// Kurze Ein-/Ausblendung (0,15 s), wie bei Streaming-Untertiteln.
    func subtitleOpacity(at t: Double?) -> Double {
        guard let t else { return 1 }
        let fade = 0.15
        var o = ((t - subtitleStart) / fade).clamped(0, 1)
        if subtitleEnd > 0.001 {
            if t > subtitleEnd { return 0 }
            o = min(o, ((subtitleEnd - t) / fade).clamped(0, 1))
        }
        return o
    }
}

// MARK: - Geometrie

struct FrameGeometry: Equatable {
    /// Größe des Bildes nach optionaler Entzerrung (Desqueeze).
    let stretchedSize: CGSize
    /// Zuschnitt in Pixeln (ganzzahlig, gerade Maße – wichtig für Video-Encoder).
    let crop: CGRect
    var outputSize: CGSize { crop.size }
}

extension AnamorphicSettings {
    func geometry(for input: CGSize) -> FrameGeometry {
        let stretchedW = Double(Stretch.outputWidth(width: Int(input.width.rounded()), desqueeze: desqueeze, edge: edgeStretch, expansion: effectiveExpansion))
        let stretchedH = input.height
        let stretched = CGSize(width: stretchedW, height: stretchedH)

        var w = stretchedW
        var h = stretchedH
        if let r = aspect.ratio {
            h = w / r
            if h > stretchedH {
                h = stretchedH
                w = h * r
            }
        }
        w = Self.evenFloor(w)
        h = Self.evenFloor(h)

        let x = ((stretchedW - w) / 2).rounded()
        // CI-Koordinaten: y wächst nach oben.
        let y = ((stretchedH - h) * (0.5 + 0.5 * verticalOffset.clamped(-1, 1))).rounded()
        return FrameGeometry(stretchedSize: stretched, crop: CGRect(x: x, y: y, width: w, height: h))
    }

    private static func evenFloor(_ v: Double) -> Double { max(2, (v / 2).rounded(.down) * 2) }
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}

// MARK: - Voreinstellungen

/// Bewusst zurückhaltende Ausgangspunkte. Alles bleibt danach frei einstellbar.
enum StylePreset: String, CaseIterable, Identifiable {
    case natural, nightCity, tungsten, goldenHour, softFilm, clean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: return "Naturell"
        case .nightCity: return "Nachtstadt"
        case .tungsten: return "Tungsten 500"
        case .goldenHour: return "Goldene Stunde"
        case .softFilm: return "Soft Film"
        case .clean: return "Nur Geometrie"
        }
    }

    var summary: String {
        switch self {
        case .natural: return "Dezenter Scope-Look, kaum sichtbare Effekte"
        case .nightCity: return "Kühle Schatten, blaue Streaks"
        case .tungsten: return "Warmes Kunstlicht-Negativ, Bernstein-Flares"
        case .goldenHour: return "Weiches Gegenlicht, warme Lichter"
        case .softFilm: return "Flach und weich, entsättigt, ruhige Szenen"
        case .clean: return "Scope-Zuschnitt mit leichter Randdehnung, keine Effekte"
        }
    }

    var settings: AnamorphicSettings {
        var s = AnamorphicSettings()
        switch self {
        case .natural:
            break
        case .nightCity:
            s.lookID = "nightBlue"
            s.lookIntensity = 0.85
            s.flareThreshold = 0.95
            s.flareIntensity = 0.45
            s.flareLength = 0.65
            s.flareTint = .blue
            s.bokehAmount = 0.22
            s.highlightBoost = 0.5
            s.grain = 0.2
            s.vignette = 0.35
        case .tungsten:
            s.lookID = "tungsten"
            s.lookIntensity = 0.9
            s.flareTint = .amber
            s.flareIntensity = 0.4
            s.halation = 0.3
            s.grain = 0.25
            s.grainSize = 0.5
        case .goldenHour:
            s.lookID = "goldenHour"
            s.lookIntensity = 0.85
            s.flareThreshold = 0.94
            s.flareTint = .amber
            s.flareIntensity = 0.3
            s.halation = 0.3
            s.warmth = 0.1
            s.grain = 0.15
        case .softFilm:
            s.lookID = "softFilm"
            s.lookIntensity = 0.9
            s.flareEnabled = false
            s.halation = 0.2
            s.edgeSoftness = 0.3
            s.grain = 0.2
            s.contrast = -0.05
        case .clean:
            s.lookID = "none"
            s.bokehEnabled = false
            s.flareEnabled = false
            s.edgeSoftness = 0
            s.halation = 0
            s.aberration = 0
            s.grain = 0
            s.vignette = 0
        }
        return s
    }
}
