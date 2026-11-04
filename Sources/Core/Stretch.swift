import Foundation
import CoreGraphics

/// Horizontale Streckung mit leichter Randbetonung ("Mumps"-Effekt echter Anamorphoten).
///
/// Ein korrekt entzerrtes Anamorphot-Bild hat in der Mitte natürliche Proportionen; nur zum Rand hin wird die
/// Abbildung bei vielen Objektiven etwas breiter gezogen (der Squeeze ist über das Bildfeld nicht ganz konstant).
/// Das Bild wird in `strips` senkrechte Streifen zerlegt; jeder bekommt den Faktor
/// s(u) = d · (1 + k · u²), u = −1 … 1 von links nach rechts, d = Mittelstreckung ("Breitenstreckung"),
/// k = `maxEdgeGain` · Randdehnung. In der Mitte gilt also genau d. Alle Streifengrenzen sind ganze Pixel,
/// damit keine Nähte entstehen.
    static let strips = 40
    /// Zusätzliche Streckung ganz am Rand bei Randdehnung = 1 (0.16 → +16 %). Echte Objektive liegen eher bei
    /// wenigen Prozent; der Standardwert (0.5) ergibt +8 % am äußersten Rand.
    static let maxEdgeGain = 0.16

    static func isIdentity(desqueeze: Double, edge: Double) -> Bool {
        desqueeze <= 1.0001 && edge <= 0.001
    }

    /// Faktor in der Bildmitte und am Rand.
    static func factors(desqueeze d: Double, edge: Double) -> (center: Double, edge: Double) {
        let dd = max(1.0, d)
        return (dd, dd * (1 + maxEdgeGain * edge.clamped(0, 1)))
    }

    /// Quell- und Zielgrenzen der Streifen (jeweils `strips + 1` ganze Zahlen).
    static func boundaries(width: Int, desqueeze: Double, edge: Double) -> (src: [Int], dst: [Int]) {
        let n = strips
        var src = [Int]()
        for i in 0...n { src.append(Int((Double(i) * Double(width) / Double(n)).rounded())) }
        if isIdentity(desqueeze: desqueeze, edge: edge) { return (src, src) }

        let f = factors(desqueeze: desqueeze, edge: edge)
        var dst = [0]
        var cum = 0.0
        for i in 0..<n {
            let mid = Double(src[i] + src[i + 1]) / 2
            let u = (mid / Double(width)) * 2 - 1
            let s = f.center + (f.edge - f.center) * u * u
            cum += Double(src[i + 1] - src[i]) * s
            dst.append(Int(cum.rounded()))
        }
        return (src, dst)
    }

    static func outputWidth(width: Int, desqueeze: Double, edge: Double) -> Int {
        boundaries(width: width, desqueeze: desqueeze, edge: edge).dst.last ?? width
    }
}
