import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Paletten

/// Eine Farbpalette besteht aus einer Akzentfarbe (Aktives, Regler, Hauptknopf) und einer Zweitfarbe ("bereit"-LED).
struct ThemePalette: Identifiable, Equatable {
    let id: String
    let name: String
    let accent: [Double]      // RGB 0…1
    let secondary: [Double]

    static let all: [ThemePalette] = [
        ThemePalette(id: "rauchrot", name: "Rauchrot", accent: [0.788, 0.482, 0.482], secondary: [0.690, 0.710, 0.737]),
        ThemePalette(id: "silber", name: "Silber", accent: [0.788, 0.808, 0.839], secondary: [0.561, 0.659, 0.784]),
        ThemePalette(id: "dunst", name: "Dunst", accent: [0.561, 0.659, 0.784], secondary: [0.788, 0.808, 0.839]),
        ThemePalette(id: "salbei", name: "Salbei", accent: [0.616, 0.722, 0.604], secondary: [0.788, 0.808, 0.839]),
        ThemePalette(id: "sand", name: "Sand", accent: [0.820, 0.725, 0.541], secondary: [0.690, 0.710, 0.737]),
        ThemePalette(id: "kupfer", name: "Kupfer", accent: [0.773, 0.541, 0.388], secondary: [0.690, 0.710, 0.737]),
    ]
    static let customID = "eigene"
    static let standard = all[0]
}

extension Color {
    init(rgb: [Double]) {
        self.init(red: rgb[0], green: rgb[1], blue: rgb[2])
    }
    /// sRGB-Komponenten (0…1)
    var rgbComponents: [Double] {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Double(r), Double(g), Double(b)]
        #else
        let c = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
        #endif
    }
}

// MARK: - Speicher

/// Hält die gewählte Palette (vorgefertigt oder selbst gemischt) und merkt sie sich zwischen Starts.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private(set) var paletteID: String
    private(set) var customAccent: [Double]
    private(set) var customSecondary: [Double]

    private enum Key {
        static let palette = "theme.palette"
        static let accent = "theme.custom.accent"
        static let secondary = "theme.custom.secondary"
    }

    private init() {
        let d = UserDefaults.standard
        paletteID = d.string(forKey: Key.palette) ?? ThemePalette.standard.id
        func rgb(_ key: String, _ fallback: [Double]) -> [Double] {
            if let v = d.array(forKey: key) as? [Double], v.count == 3 { return v }
            return fallback
        }
        customAccent = rgb(Key.accent, ThemePalette.standard.accent)
        customSecondary = rgb(Key.secondary, ThemePalette.standard.secondary)
    }

    var isCustom: Bool { paletteID == ThemePalette.customID }

    private var current: ThemePalette? { ThemePalette.all.first { $0.id == paletteID } }
    var accent: Color { Color(rgb: current?.accent ?? customAccent) }
    var secondary: Color { Color(rgb: current?.secondary ?? customSecondary) }

    func select(_ id: String) {
        // Beim Wechsel zu "Eigene" mit der bisherigen Palette beginnen
        if id == ThemePalette.customID, let p = current {
            customAccent = p.accent
            customSecondary = p.secondary
            save()
        }
        paletteID = id
        UserDefaults.standard.set(id, forKey: Key.palette)
    }

    func setCustomAccent(_ color: Color) {
        customAccent = color.rgbComponents
        paletteID = ThemePalette.customID
        save()
    }

    func setCustomSecondary(_ color: Color) {
        customSecondary = color.rgbComponents
        paletteID = ThemePalette.customID
        save()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(paletteID, forKey: Key.palette)
        d.set(customAccent, forKey: Key.accent)
        d.set(customSecondary, forKey: Key.secondary)
    }
}

// MARK: - Auswahl

/// Kleiner Farbpunkt in der oberen Leiste; öffnet die Palettenauswahl.
struct PaletteButton: View {
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            ZStack {
                Circle().fill(Theme.accent).frame(width: 14, height: 14)
                Circle().stroke(Theme.faint, lineWidth: 1).frame(width: 22, height: 22)
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Farbpalette")
        .popover(isPresented: $open, arrowEdge: .top) {
            PaletteList()
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct PaletteList: View {
    private var store: ThemeStore { ThemeStore.shared }

    var body: some View {
        let selected = store.paletteID
        return VStack(alignment: .leading, spacing: 10) {
            Text("Farbpalette").gateCaption(Theme.dim)

            ForEach(ThemePalette.all) { p in
                Button { store.select(p.id) } label: {
                    HStack(spacing: 10) {
                        swatch(Color(rgb: p.accent), Color(rgb: p.secondary))
                        Text(p.name).gateCaption(selected == p.id ? Theme.text : Theme.dim)
                        Spacer(minLength: 12)
                        LED(on: selected == p.id, color: Color(rgb: p.accent), size: 7)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            DottedLine()

            HStack(spacing: 10) {
                swatch(Color(rgb: store.customAccent), Color(rgb: store.customSecondary))
                Text("Eigene").gateCaption(store.isCustom ? Theme.text : Theme.dim)
                Spacer(minLength: 12)
                LED(on: store.isCustom, color: Color(rgb: store.customAccent), size: 7)
            }
            .contentShape(Rectangle())
            .onTapGesture { store.select(ThemePalette.customID) }

            HStack(spacing: 14) {
                ColorPicker("Akzent", selection: Binding(
                    get: { Color(rgb: store.customAccent) },
                    set: { store.setCustomAccent($0) }), supportsOpacity: false)
                ColorPicker("Zweit", selection: Binding(
                    get: { Color(rgb: store.customSecondary) },
                    set: { store.setCustomSecondary($0) }), supportsOpacity: false)
            }
            .font(Theme.mono(11))
            .foregroundStyle(Theme.dim)
        }
        .padding(16)
        .frame(width: 250)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }

    private func swatch(_ a: Color, _ b: Color) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(a)
            Rectangle().fill(b)
        }
        .frame(width: 30, height: 14)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.faint, lineWidth: 1))
    }
}
