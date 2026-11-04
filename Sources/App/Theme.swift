import SwiftUI

// Designsprache "Dot"
//
// Technisches, spielerisches Gerätedesign im Sinne von Teenage Engineering und Nothing: reines Schwarz,
// Punktmatrix-Schrift für Werte und Logo, Monospace-Versalien als Beschriftung, Kapsel-Schalter mit LED,
// Segmentbalken statt Standard-Slider. Eine gedämpfte Akzentfarbe für Aktives (wählbare Paletten oder selbst gemischt).
// Nur Dark Mode.
enum Theme {
    static let bg = Color(red: 0, green: 0, blue: 0)                              // #000000
    static let panel = Color(red: 0.039, green: 0.039, blue: 0.043)               // #0A0A0B
    static let raised = Color(red: 0.086, green: 0.086, blue: 0.094)              // #161618
    static let hairline = Color(red: 0.165, green: 0.165, blue: 0.176)            // #2A2A2D
    static let text = Color(red: 0.949, green: 0.949, blue: 0.957)                // #F2F2F4
    static let dim = Color(red: 0.549, green: 0.549, blue: 0.576)                 // #8C8C93
    static let faint = Color(red: 0.294, green: 0.294, blue: 0.314)               // #4B4B50
    /// Akzentfarbe: kommt aus der gewählten Palette (siehe ThemeStore), Standard ist ein gedämpftes, silbriges Rot.
    static var accent: Color { ThemeStore.shared.accent }
    /// Zweitfarbe der Palette (z. B. "bereit"-LED)
    static var secondary: Color { ThemeStore.shared.secondary }
    static var warn: Color { accent }

    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Titel: ruhige, mittelstarke Grotesk (Name aus Kompatibilitätsgründen unverändert)
    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .default) }

    #if os(iOS)
    static let sliderInset: CGFloat = 4
    #else
    static let sliderInset: CGFloat = 2
    #endif
}

// MARK: - Textstile

extension View {
    /// Kleine, gesperrte Mono-Versalien-Beschriftung
    func gateCaption(_ color: Color = Theme.dim) -> some View {
        self.font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    func readout(_ color: Color = Theme.text, size: CGFloat = 12) -> some View {
        self.font(Theme.mono(size))
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

// MARK: - Punktmatrix-Schrift

/// 5×7-Punktmatrix-Zeichen (A–Z, 0–9, einige Sonderzeichen). Zeile für Zeile, 1 = Punkt.
enum DotFont {
    static let glyphs: [Character: [String]] = [
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
        "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
        "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
        ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
        "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
        "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
        "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
    ]

    /// Malzeichen (kleines ×)
    static let times = ["00000", "10001", "01010", "00100", "01010", "10001", "00000"]

    static func normalized(_ c: Character) -> Character {
        let u = String(c).uppercased()
        return u.count == 1 ? u.first! : c
    }

    /// Alle Zeichen vorhanden (Leerzeichen zählen als vorhanden)?
    static func supports(_ text: String) -> Bool {
        text.allSatisfy { c in
            c == " " || c == "×" || glyphs[normalized(c)] != nil
        }
    }

    static func rows(for c: Character) -> [String]? {
        if c == "×" { return times }
        return glyphs[normalized(c)]
    }

    /// Breite in Punkten (Raster-Einheiten) für den Text.
    static func columns(of text: String) -> Int {
        var n = 0
        for c in text { n += (c == " " ? 3 : 6) }
        return max(0, n - 1)
    }
}

/// Zeichnet Text als Punktmatrix. `dot` ist der Punktdurchmesser, Raster = 1.35 × Durchmesser.
struct DotText: View {
    let text: String
    var dot: CGFloat = 3
    var color: Color = Theme.text
    var unlit: Color? = nil          // Optional: nicht leuchtende Punkte schwach andeuten

    private var pitch: CGFloat { dot * 1.38 }

    var body: some View {
        let cols = DotFont.columns(of: text)
        Canvas { ctx, size in
            var x: CGFloat = 0
            for ch in text {
                if ch == " " { x += 3 * pitch; continue }
                guard let rows = DotFont.rows(for: ch) else { x += 6 * pitch; continue }
                for (ry, row) in rows.enumerated() {
                    for (cx, bit) in row.enumerated() {
                        let rect = CGRect(x: x + CGFloat(cx) * pitch, y: CGFloat(ry) * pitch, width: dot, height: dot)
                        if bit == "1" {
                            ctx.fill(Path(ellipseIn: rect), with: .color(color))
                        } else if let unlit {
                            ctx.fill(Path(ellipseIn: rect), with: .color(unlit))
                        }
                    }
                }
                x += 6 * pitch
            }
        }
        .frame(width: CGFloat(max(1, cols)) * pitch + dot, height: 7 * pitch)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// Wert als Punktmatrix, wenn alle Zeichen im Dot-Font vorhanden sind, sonst als Mono-Text.
struct DotValue: View {
    let text: String
    var color: Color = Theme.text
    var dot: CGFloat = 2.2

    var body: some View {
        if DotFont.supports(text) {
            DotText(text: text, dot: dot, color: color)
        } else {
            Text(text).readout(color, size: 12)
        }
    }
}

/// Dezentes Punktraster als Hintergrund (wie das Raster eines Sequenzers).
struct DotGrid: View {
    var spacing: CGFloat = 16
    var color: Color = Color(red: 0.11, green: 0.11, blue: 0.12)

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)), with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// Kleine LED (Punkt)
struct LED: View {
    var on: Bool
    var color: Color = Theme.accent
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(on ? color : Color.clear)
            .overlay(Circle().stroke(on ? color : Theme.faint, lineWidth: 1))
            .frame(width: size, height: size)
            .shadow(color: on ? color.opacity(0.6) : .clear, radius: 3)
            .animation(.easeOut(duration: 0.15), value: on)
    }
}

// MARK: - Abschnittskopf

/// Gepunktete Trennlinie
struct DottedLine: View {
    var color: Color = Theme.faint
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0.5
            while x < size.width {
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: size.height / 2 - 0.6, width: 1.2, height: 1.2)), with: .color(color))
                x += 4.5
            }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                Text(title).gateCaption(Theme.text)
                Spacer()
                if let trailing { Text(trailing).gateCaption(Theme.faint) }
            }
            DottedLine()
        }
    }
}

// MARK: - Segment-Regler

/// Regler als Reihe kleiner Leuchtsegmente mit Punktmatrix-Anzeige. Bedienung per Ziehen oder Tippen,
/// Doppeltippen auf die Beschriftung setzt den Standardwert; VoiceOver kann den Wert schrittweise ändern.
struct ScaleSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var neutral: Double? = nil
    var defaultValue: Double? = nil
    var format: (Double) -> String = { String(format: "%.2f", $0) }

    @State private var active = false

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? ((value - range.lowerBound) / span).clamped(0, 1) : 0
    }

    var body: some View {
        // Vor dem Canvas lesen, damit eine Palettenänderung die Ansicht neu zeichnet
        let accent = Theme.accent
        return VStack(spacing: 7) {
            HStack(alignment: .center) {
                Text(title).gateCaption(active ? Theme.text : Theme.dim)
                Spacer()
                DotValue(text: format(value), color: active ? accent : Theme.text)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { if let d = defaultValue { value = d } }
            GeometryReader { geo in
                ZStack {
                    Canvas { ctx, size in
                        let inset = Theme.sliderInset
                        let usable = size.width - inset * 2
                        let segments = 36
                        let gap: CGFloat = 2.5
                        let w = (usable - gap * CGFloat(segments - 1)) / CGFloat(segments)
                        let neutralIndex: Int? = neutral.map {
                            let nf = (($0 - range.lowerBound) / (range.upperBound - range.lowerBound)).clamped(0, 1)
                            return Int((nf * Double(segments - 1)).rounded())
                        }
                        let lit = Int((fraction * Double(segments)).rounded())

                        for i in 0..<segments {
                            let x = inset + CGFloat(i) * (w + gap)
                            let isLit: Bool
                            if let n = neutralIndex {
                                // Bipolare Regler leuchten von der Neutralmarke aus
                                let cur = Int((fraction * Double(segments - 1)).rounded())
                                isLit = (i >= min(n, cur) && i <= max(n, cur)) && !(cur == n && i != n)
                            } else {
                                isLit = i < lit
                            }
                            let h: CGFloat = (i % 6 == 0) ? 16 : 12
                            let rect = CGRect(x: x, y: size.height - h, width: w, height: h)
                            let path = Path(roundedRect: rect, cornerRadius: 1.2)
                            ctx.fill(path, with: .color(isLit ? (active ? accent : Theme.text) : Theme.hairline))
                        }
                        // Neutralmarke
                        if let n = neutralIndex {
                            let x = inset + CGFloat(n) * (w + gap) + w / 2
                            ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: 0, width: 3, height: 3)), with: .color(Theme.dim))
                        }
                    }
                    .allowsHitTesting(false)

                    // Eigene Bedienung per Ziehen oder Tippen (der frühere unsichtbare System-Slider nahm keine Eingaben an)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { g in
                                    active = true
                                    set(x: g.location.x, width: geo.size.width)
                                }
                                .onEnded { _ in active = false }
                        )
                }
            }
            .frame(height: 28)
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(format(value))
            .accessibilityAdjustableAction { direction in
                let step = (range.upperBound - range.lowerBound) / 20
                switch direction {
                case .increment: value = min(range.upperBound, value + step)
                case .decrement: value = max(range.lowerBound, value - step)
                @unknown default: break
                }
            }
        }
    }

    private func set(x: CGFloat, width: CGFloat) {
        let inset = Theme.sliderInset
        let usable = max(1, width - inset * 2)
        let f = Double(((x - inset) / usable)).clamped(0, 1)
        var v = range.lowerBound + f * (range.upperBound - range.lowerBound)
        // Neutralpunkt rastet leicht ein
        if let n = neutral, abs(v - n) < (range.upperBound - range.lowerBound) * 0.015 { v = n }
        value = v
    }
}

// MARK: - Auswahl-Leiste

/// Kapsel-Segmente. Die aktive Auswahl ist weiß hinterlegt (wie eine gedrückte Taste).
struct OptionStrip<T: Hashable & Identifiable>: View {
    let items: [T]
    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let on = item == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = item } } label: {
                    Text(title(item))
                        .font(Theme.mono(11, weight: on ? .semibold : .regular))
                        .textCase(.uppercase)
                        .foregroundStyle(on ? Theme.bg : Theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(on ? Theme.text : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Schalter

struct LampToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { withAnimation(.snappy(duration: 0.2)) { isOn.toggle() } } label: {
            HStack(spacing: 12) {
                Text(title).gateCaption(isOn ? Theme.text : Theme.dim)
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? Theme.accent : Theme.raised)
                    Capsule().stroke(isOn ? Theme.accent : Theme.faint, lineWidth: 1)
                    Circle().fill(isOn ? Theme.bg : Theme.dim).frame(width: 14, height: 14).padding(3)
                }
                .frame(width: 40, height: 20)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "An" : "Aus")
    }
}

// MARK: - Buttons

struct GateButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(background(pressed: configuration.isPressed)))
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.4)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.bg
        case .secondary: return Theme.text
        case .quiet: return Theme.dim
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary: return Theme.accent
        case .secondary: return Theme.faint
        case .quiet: return Color.clear
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: return pressed ? Theme.accent.opacity(0.8) : Theme.accent
        case .secondary: return pressed ? Theme.raised : Color.clear
        case .quiet: return pressed ? Theme.raised : Color.clear
        }
    }
}

// MARK: - Sucher-Marken

/// L-förmige Eckmarken wie Framelines im Kamerasucher.
struct ViewfinderMarks: View {
    var length: CGFloat = 14
    var color: Color = Theme.accent

    var body: some View {
        Canvas { ctx, size in
            func corner(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
                var p = Path()
                p.move(to: CGPoint(x: x + dx * length, y: y))
                p.addLine(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x, y: y + dy * length))
                ctx.stroke(p, with: .color(color), lineWidth: 1.5)
            }
            corner(0.5, 0.5, 1, 1)
            corner(size.width - 0.5, 0.5, -1, 1)
            corner(0.5, size.height - 0.5, 1, -1)
            corner(size.width - 0.5, size.height - 0.5, -1, -1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Werteformat

enum Fmt {
    static func percent(_ v: Double) -> String { String(format: "%.0f", v * 100) }
    static func signed(_ v: Double) -> String { String(format: "%+.2f", v) }
    static func signedPercent(_ v: Double) -> String { String(format: "%+.0f", v * 100) }
    static func ev(_ v: Double) -> String { String(format: "%+.1f EV", v) }
    static func ratio(_ v: Double) -> String { String(format: "%.2f : 1", v) }
    static func factor(_ v: Double) -> String { String(format: "%.2f×", v) }
    static func time(_ v: Double) -> String {
        let t = max(0, v)
        return String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }
}
