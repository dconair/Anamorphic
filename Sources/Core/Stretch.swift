import Foundation
import CoreGraphics

/// Nichtlineare horizontale Streckung: Breitenstreckung, Rand-Mumps und Bildwinkel-Erweiterung.
///
/// Das Bild wird in `strips` senkrechte Streifen zerlegt. Jeder Streifen bekommt einen eigenen Faktor
/// s(u) mit u = −1 … 1 (links nach rechts):
///
///     s(u) = d · (1 + k · u² + x(u))
///
/// - `d`  Breitenstreckung (Standard 1.00: Mitte bleibt unverändert)
/// - `k`  Rand-Mumps: `maxEdgeGain` · Randdehnung, wenige Prozent am äußersten Rand
/// - `x`  Bildwinkel-Erweiterung: Innerhalb von |u| ≤ `expansionCore` null (Mitte bleibt exakt wie das Original),
///        außerhalb quadratisch ansteigend. Der Anstieg ist so gewählt, dass die Bildbreite insgesamt um den
///        Faktor `expansion` zunimmt. Das Bild wird also nicht überall gleich gestreckt, sondern nur die
///        Randzonen werden weiter gedehnt, ähnlich wie bei einem Weitwinkel-Objektiv. Dort lässt die weichere Abbildung
///        die Streckung kaum auffallen, die Bildmitte behält natürliche Proportionen.
///
/// Alle Streifengrenzen sind ganze Pixel, damit keine Nähte entstehen.
enum Stretch {
    static let strips = 64
    /// Zusätzliche Streckung ganz am Rand bei Randdehnung = 1 (0.16 → +16 %). Echte Objektive liegen eher bei
    /// wenigen Prozent; der Standardwert (0.5) ergibt +8 % am äußersten Rand.
    static let maxEdgeGain = 0.16
    /// Anteil der halben Bildbreite, der bei der Erweiterung unverändert bleibt (0.4 → mittlere 40 %).
    static let expansionCore = 0.4

    static func isIdentity(desqueeze: Double, edge: Double, expansion: Double = 1) -> Bool {
        desqueeze <= 1.0001 && edge <= 0.001 && expansion <= 1.0001
    }

    /// Faktor in der Bildmitte und am äußersten Rand.
    static func factors(desqueeze d: Double, edge: Double, expansion: Double = 1) -> (center: Double, edge: Double) {
        let dd = max(1.0, d)
        return (factor(at: 0, desqueeze: dd, edge: edge, expansion: expansion),
                factor(at: 1, desqueeze: dd, edge: edge, expansion: expansion))
    }

    /// Streckfaktor an der normierten Position u (−1 … 1).
    static func factor(at u: Double, desqueeze d: Double, edge: Double, expansion: Double) -> Double {
        let uu = abs(u).clamped(0, 1)
        var gain = maxEdgeGain * edge.clamped(0, 1) * uu * uu
        let x = max(1.0, expansion)
        if x > 1.0001, uu > expansionCore {
            let t = (uu - expansionCore) / (1 - expansionCore)
            // Integral über beide Randzonen / Gesamtbreite = (x − 1)  ⇒  g = 3 (x − 1) / (1 − core)
            let g = 3 * (x - 1) / (1 - expansionCore)
            gain += g * t * t
        }
        return max(1.0, d) * (1 + gain)
    }

    /// Quell- und Zielgrenzen der Streifen (jeweils `strips + 1` ganze Zahlen).
    static func boundaries(width: Int, desqueeze: Double, edge: Double, expansion: Double = 1) -> (src: [Int], dst: [Int]) {
        let n = strips
        var src = [Int]()
        for i in 0...n { src.append(Int((Double(i) * Double(width) / Double(n)).rounded())) }
        if isIdentity(desqueeze: desqueeze, edge: edge, expansion: expansion) { return (src, src) }

        var dst = [0]
        var cum = 0.0
        for i in 0..<n {
            let mid = Double(src[i] + src[i + 1]) / 2
            let u = (mid / Double(width)) * 2 - 1
            let s = factor(at: u, desqueeze: desqueeze, edge: edge, expansion: expansion)
            cum += Double(src[i + 1] - src[i]) * s
            dst.append(Int(cum.rounded()))
        }
        return (src, dst)
    }

    static func outputWidth(width: Int, desqueeze: Double, edge: Double, expansion: Double = 1) -> Int {
        boundaries(width: width, desqueeze: desqueeze, edge: edge, expansion: expansion).dst.last ?? width
    }
}
