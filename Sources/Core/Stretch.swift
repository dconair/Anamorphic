import Foundation
import CoreGraphics

/// Horizontale Streckung mit Randbetonung ("Mumps-Effekt" echter Anamorphoten).
///
/// Ein Anamorphot bildet die Mitte annähernd unverzerrt ab, der Rand wird dagegen stärker in die
/// Breite gezogen. Das Bild wird in `strips` senkrechte Streifen zerlegt; jeder Streifen bekommt
/// einen eigenen Faktor s(u) = c + (e − c)·u² (u = −1 … 1 von links nach rechts). c und e werden so
/// gewählt, dass die mittlere Streckung genau `desqueeze` ergibt. Alle Streifengrenzen sind ganze
/// Pixel, damit keine Nähte entstehen.
enum Stretch {
    static let strips = 40

    static func isIdentity(desqueeze: Double, edge: Double) -> Bool {
        desqueeze <= 1.0001 && edge <= 0.001
    }

    /// Faktor in der Bildmitte und am Rand.
    static func factors(desqueeze d: Double, edge: Double) -> (center: Double, edge: Double) {
        let dd = max(1.0, d)
        let e = dd * (1 + 0.6 * edge.clamped(0, 1))
        let c = (3 * dd - e) / 2
        return (c, e)
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
