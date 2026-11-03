import SwiftUI

// Designsprache "Gate"
//
// Orientiert sich an der Haptik von Kinoobjektiven und Cinema-Kameras, nicht an typischen Foto-Apps:
//  • mattes, warmes Schwarz wie ein Filmgate – keine Verläufe, keine Schatten, keine Glas-Karten
//  • Skalen mit Strichmarkierungen statt Standard-Slider (wie der Entfernungsring eines Objektivs)
//  • ein einziger Akzent: Wolfram-Bernstein (Tungsten) – Kunstlicht-Gelb, wie ein Indexstrich am Ring
//  • Werte in Monospace-Ziffern (Kamera-Readout), Beschriftungen als kleine, gesperrte Versalien
//  • Titel in Serif (Filmabspann), alles andere in der System-Grotesk
//  • kleine Radien (2 pt), Haarlinien statt Flächen
enum Theme {
    static let bg = Color(red: 0.055, green: 0.055, blue: 0.049)        // #0E0E0D
    static let panel = Color(red: 0.082, green: 0.082, blue: 0.074)     // #151513
    static let raised = Color(red: 0.118, green: 0.114, blue: 0.102)    // #1E1D1A
    static let hairline = Color(red: 0.200, green: 0.192, blue: 0.172)  // #333128
    static let text = Color(red: 0.910, green: 0.894, blue: 0.851)      // #E8E4D9
    static let dim = Color(red: 0.553, green: 0.533, blue: 0.482)       // #8D887B
    static let faint = Color(red: 0.353, green: 0.341, blue: 0.306)     // #5A574E
    static let accent = Color(red: 0.851, green: 0.643, blue: 0.255)    // #D9A441 Tungsten
    static let warn = Color(red: 0.769, green: 0.333, blue: 0.231)      // #C4553B

    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }

    #if os(iOS)
    static let sliderInset: CGFloat = 15
    #else
    static let sliderInset: CGFloat = 9
    #endif
}

// MARK: - Textstile

extension View {
    /// Kleine, gesperrte Versalien-Beschriftung
    func gateCaption(_ color: Color = Theme.dim) -> some View {
        self.font(.system(size: 10, weight: .semibold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    func readout(_ color: Color = Theme.text, size: CGFloat = 12) -> some View {
        self.font(Theme.mono(size))
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

// MARK: - Abschnittskopf

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).gateCaption(Theme.accent)
                Spacer()
                if let trailing { Text(trailing).gateCaption(Theme.faint) }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

// MARK: - Skalen-Regler

/// Regler im Stil eines Objektivrings: Strichskala, Indexmarke, Mono-Anzeige.
/// Die Bedienung übernimmt ein (fast) unsichtbarer System-Slider – das behält Scrollverhalten,
/// Tastatur- und VoiceOver-Bedienung bei.
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
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).gateCaption(active ? Theme.text : Theme.dim)
                Spacer()
                Text(format(value)).readout(active ? Theme.accent : Theme.text)
            }
            ZStack {
                Canvas { ctx, size in
                    let inset = Theme.sliderInset
                    let usable = size.width - inset * 2
                    let steps = 40
                    let baseY = size.height - 2

                    // Skalenstriche
                    for i in 0...steps {
                        let x = inset + usable * CGFloat(i) / CGFloat(steps)
                        let major = i % 10 == 0
                        let mid = i % 5 == 0
                        let h: CGFloat = major ? 12 : (mid ? 8 : 4)
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: baseY))
                        p.addLine(to: CGPoint(x: x, y: baseY - h))
                        ctx.stroke(p, with: .color(major ? Theme.dim : Theme.faint), lineWidth: 1)
                    }

                    // Neutralmarke (z. B. 0 bei Korrekturreglern)
                    if let neutral {
                        let nf = (neutral - range.lowerBound) / (range.upperBound - range.lowerBound)
                        let nx = inset + usable * CGFloat(nf)
                        var p = Path()
                        p.move(to: CGPoint(x: nx, y: baseY + 1))
                        p.addLine(to: CGPoint(x: nx, y: baseY - 15))
                        ctx.stroke(p, with: .color(Theme.text.opacity(0.55)), lineWidth: 1)
                    }

                    // Indexmarke
                    let ix = inset + usable * CGFloat(fraction)
                    var idx = Path()
                    idx.move(to: CGPoint(x: ix, y: baseY + 1))
                    idx.addLine(to: CGPoint(x: ix, y: 1))
                    ctx.stroke(idx, with: .color(Theme.accent), lineWidth: 2)
                }
                .allowsHitTesting(false)

                Slider(value: $value, in: range) { editing in active = editing }
                    .opacity(0.02)
                    .accessibilityLabel(title)
            }
            .frame(height: 24)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if let d = defaultValue { value = d }
        }
    }
}

// MARK: - Auswahl-Leiste

/// Textauswahl mit Indexstrich statt Segmented-Control.
struct OptionStrip<T: Hashable & Identifiable>: View {
    let items: [T]
    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let on = item == selection
                Button { selection = item } label: {
                    VStack(spacing: 6) {
                        Text(title(item))
                            .font(Theme.mono(11, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Theme.text : Theme.dim)
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(on ? Theme.accent : Theme.hairline).frame(height: on ? 2 : 1)
                    }
                    .padding(.top, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: - Schalter

struct LampToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(isOn ? Theme.accent : Color.clear)
                    .overlay(Rectangle().stroke(isOn ? Theme.accent : Theme.faint, lineWidth: 1))
                    .frame(width: 9, height: 9)
                Text(title).gateCaption(isOn ? Theme.text : Theme.dim)
                Spacer()
                Text(isOn ? "AN" : "AUS").font(Theme.mono(10)).foregroundStyle(isOn ? Theme.accent : Theme.faint)
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
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(background(pressed: configuration.isPressed))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 2))
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
        case .secondary: return Theme.hairline
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
    var color: Color = Theme.dim

    var body: some View {
        Canvas { ctx, size in
            func corner(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
                var p = Path()
                p.move(to: CGPoint(x: x + dx * length, y: y))
                p.addLine(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x, y: y + dy * length))
                ctx.stroke(p, with: .color(color), lineWidth: 1)
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
