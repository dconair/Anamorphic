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
    var desqueeze: Double = 1.0             // 1.0 ... 1.5, nur für echtes Anamorphot-Material

    // Bokeh
    var bokehEnabled = true
    var bokehAmount = 0.35                  // 0 ... 1
    var bokehOval = 1.6                     // 1 ... 2   (Verhältnis Breite:Höhe der Unschärfescheiben)
    var highlightBoost = 0.5                // 0 ... 1   Lichter werden zu Scheiben
    var focusMode: FocusMode = .subject
    var focusX = 0.5                        // 0 ... 1 (Ellipse)
    var focusY = 0.55
    var focusSize = 0.42                    // 0.1 ... 1
    var focusFeather = 0.5                  // 0 ... 1

    // Flares
    var flareEnabled = true
    var flareThreshold = 0.96               // 0.7 ... 1  (Anzeige-Helligkeit ab der Lichter streuen)
    var flareLength = 0.55                  // 0 ... 1
    var flareIntensity = 0.45               // 0 ... 1
    var flareTint: FlareTint = .blue
    var halation = 0.25                     // 0 ... 1  warmer Glimmer um Lichter

    // Optik
    var aberration = 0.2                    // 0 ... 1  laterale Farbsäume zum Rand

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
    var subtitlePosition = 0.09             // Abstand der Unterkante, Anteil der Bildhöhe (0 ... 0.4)

    // Film
    var grain = 0.3                         // 0 ... 1
    var grainSize = 0.4                     // 0 ... 1
    var vignette = 0.3                      // 0 ... 1
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
        let stretchedW = input.width * max(1.0, desqueeze)
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
    case natural, nightCity, tungsten, goldenHour, clean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: return "Naturell"
        case .nightCity: return "Nachtstadt"
        case .tungsten: return "Tungsten 500"
        case .goldenHour: return "Goldene Stunde"
        case .clean: return "Nur Format"
        }
    }

    var summary: String {
        switch self {
        case .natural: return "Dezenter Scope-Look, kaum sichtbare Effekte"
        case .nightCity: return "Kühle Schatten, blaue Streaks"
        case .tungsten: return "Warmes Kunstlicht-Negativ, Bernstein-Flares"
        case .goldenHour: return "Weiches Gegenlicht, warme Lichter"
        case .clean: return "2.39:1 Zuschnitt, sonst nichts"
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
            s.flareThreshold = 0.93
            s.flareIntensity = 0.6
            s.flareLength = 0.7
            s.flareTint = .blue
            s.bokehAmount = 0.5
            s.highlightBoost = 0.7
            s.grain = 0.35
            s.vignette = 0.4
        case .tungsten:
            s.lookID = "tungsten"
            s.lookIntensity = 0.9
            s.flareTint = .amber
            s.flareIntensity = 0.4
            s.halation = 0.4
            s.grain = 0.4
            s.grainSize = 0.5
        case .goldenHour:
            s.lookID = "goldenHour"
            s.lookIntensity = 0.85
            s.flareThreshold = 0.94
            s.flareTint = .amber
            s.flareIntensity = 0.35
            s.halation = 0.35
            s.warmth = 0.1
            s.grain = 0.25
        case .clean:
            s.lookID = "none"
            s.bokehEnabled = false
            s.flareEnabled = false
            s.halation = 0
            s.aberration = 0
            s.grain = 0
            s.vignette = 0
        }
        return s
    }
}
