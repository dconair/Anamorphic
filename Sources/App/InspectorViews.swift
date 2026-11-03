import SwiftUI

// MARK: - Inspector (Reiter + Inhalt)

struct InspectorView: View {
    @Bindable var model: AppModel
    let importLUT: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                OptionStrip(items: InspectorTab.allCases, selection: $model.tab) { $0.title }
                    .frame(minWidth: 360)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 4)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    switch model.tab {
                    case .look: LookPanel(model: model, importLUT: importLUT)
                    case .lens: LensPanel(model: model)
                    case .flare: FlarePanel(model: model)
                    case .color: ColorPanel(model: model)
                    case .film: FilmPanel(model: model)
                    case .titles: TitlePanel(model: model)
                    case .export: ExportPanel(model: model)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.panel)
    }
}

// MARK: - Wiederverwendbare Bausteine

/// Regler, der direkt an einen Wert in `AnamorphicSettings` gebunden ist. Doppeltipp = Standardwert.
private struct Param: View {
    @Bindable var model: AppModel
    let title: String
    let keyPath: WritableKeyPath<AnamorphicSettings, Double>
    let range: ClosedRange<Double>
    var neutral: Double? = nil
    var format: (Double) -> String = Fmt.percent

    var body: some View {
        ScaleSlider(
            title: title,
            value: Binding(get: { model.settings[keyPath: keyPath] },
                           set: { model.settings[keyPath: keyPath] = $0 }),
            range: range,
            neutral: neutral,
            defaultValue: AnamorphicSettings()[keyPath: keyPath],
            format: format
        )
    }
}

private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Group_<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: title, trailing: trailing)
            content
        }
    }
}

// MARK: - Look

private struct LookPanel: View {
    @Bindable var model: AppModel
    let importLUT: () -> Void

    var body: some View {
        Group_(title: "Voreinstellung") {
            VStack(spacing: 0) {
                ForEach(StylePreset.allCases) { preset in
                    Button { model.apply(preset: preset) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(preset.title).font(Theme.serif(15)).foregroundStyle(Theme.text)
                            Spacer()
                            Text(preset.summary).font(.system(size: 11)).foregroundStyle(Theme.dim)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 1)
                }
            }
        }

        Group_(title: "Look / LUT") {
            VStack(spacing: 0) {
                ForEach(LookLibrary.all) { look in
                    LookRow(title: look.title, subtitle: look.subtitle,
                            swatches: swatches(for: look.recipe),
                            selected: model.settings.lookID == look.id) {
                        model.settings.lookID = look.id
                    }
                }
                if let custom = model.customLUT {
                    LookRow(title: custom.title, subtitle: "Eigene LUT · \(custom.size)³",
                            swatches: swatches(for: custom),
                            selected: model.settings.lookID == "custom") {
                        model.settings.lookID = "custom"
                    }
                }
            }
            Button("LUT importieren (.cube)", action: importLUT)
                .buttonStyle(GateButtonStyle(kind: .secondary))

            Param(model: model, title: "Stärke", keyPath: \.lookIntensity, range: 0...1)

            VStack(alignment: .leading, spacing: 6) {
                Text("Farbraum der LUT").gateCaption()
                OptionStrip(items: LUTSpace.allCases, selection: $model.settings.lutSpace) { $0.title }
                Hint("Die meisten Film-LUTs sind für Rec.709 gebaut. Bei LUTs für Display P3 oder sRGB hier umstellen, sonst wirken Farben leicht verschoben.")
            }
        }
    }

    private func swatches(for recipe: LookRecipe) -> [Color] {
        LookLibrary.swatchInputs.map { i in
            let o = recipe.apply(i.0, i.1, i.2)
            return Color(red: Double(o.0), green: Double(o.1), blue: Double(o.2))
        }
    }

    private func swatches(for lut: CubeLUT) -> [Color] {
        LookLibrary.swatchInputs.map { i in
            // Nächster Gitterpunkt reicht für eine Farbvorschau
            let n = lut.size - 1
            let r = Int((i.0 * Float(n)).rounded()), g = Int((i.1 * Float(n)).rounded()), b = Int((i.2 * Float(n)).rounded())
            let idx = ((b * lut.size + g) * lut.size + r) * 3
            guard idx + 2 < lut.rgb.count else { return .gray }
            return Color(red: Double(lut.rgb[idx]), green: Double(lut.rgb[idx + 1]), blue: Double(lut.rgb[idx + 2]))
        }
    }
}

private struct LookRow: View {
    let title: String
    let subtitle: String
    let swatches: [Color]
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Rectangle().fill(selected ? Theme.accent : Color.clear).frame(width: 2)
                HStack(spacing: 0) {
                    ForEach(swatches.indices, id: \.self) { Rectangle().fill(swatches[$0]) }
                }
                .frame(width: 64, height: 22)
                .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Theme.text : Theme.dim)
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                }
                Spacer()
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Linse

private struct LensPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        Group_(title: "Bildformat") {
            OptionStrip(items: AspectTarget.allCases, selection: $model.settings.aspect) { $0.title }
            Param(model: model, title: "Ausschnitt vertikal", keyPath: \.verticalOffset, range: -1...1,
                  neutral: 0, format: Fmt.signedPercent)
            Param(model: model, title: "Desqueeze", keyPath: \.desqueeze, range: 1...1.5, format: Fmt.factor)
            Hint("Desqueeze streckt das Bild in die Breite – nur sinnvoll für Material, das wirklich mit einem Anamorphot (z. B. 1.33× Vorsatz) gedreht wurde. Normale Aufnahmen bleiben bei 1.00×; sie werden dann nur sauber auf das Format zugeschnitten, nichts wird verzerrt.")
        }

        Group_(title: "Bokeh") {
            LampToggle(title: "Anamorphes Bokeh", isOn: $model.settings.bokehEnabled)
            if model.settings.bokehEnabled {
                Param(model: model, title: "Unschärfe", keyPath: \.bokehAmount, range: 0...1)
                Param(model: model, title: "Ovalität", keyPath: \.bokehOval, range: 1...2, format: Fmt.ratio)
                Param(model: model, title: "Lichter-Scheiben", keyPath: \.highlightBoost, range: 0...1)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Schärfezone").gateCaption()
                    OptionStrip(items: FocusMode.allCases, selection: $model.settings.focusMode) { $0.title }
                    if model.settings.focusMode == .subject {
                        Hint(model.media == .video
                             ? "Im Video wird aus Geschwindigkeitsgründen die Ellipse verwendet. Die Motiverkennung gilt für Fotos."
                             : "Das Motiv wird automatisch erkannt. Wird nichts erkannt, greift die Ellipse.")
                    }
                }

                if model.settings.focusMode == .ellipse || model.media == .video {
                    Param(model: model, title: "Zone horizontal", keyPath: \.focusX, range: 0...1)
                    Param(model: model, title: "Zone vertikal", keyPath: \.focusY, range: 0...1)
                    Param(model: model, title: "Zonengröße", keyPath: \.focusSize, range: 0.1...1)
                }
                Param(model: model, title: "Übergang", keyPath: \.focusFeather, range: 0...1)
            }
        }

        Group_(title: "Optik") {
            Param(model: model, title: "Farbsäume am Rand", keyPath: \.aberration, range: 0...1)
        }
    }
}

// MARK: - Flare

private struct FlarePanel: View {
    @Bindable var model: AppModel

    var body: some View {
        Group_(title: "Streak-Flares") {
            LampToggle(title: "Horizontale Streaks", isOn: $model.settings.flareEnabled)
            if model.settings.flareEnabled {
                Param(model: model, title: "Schwelle", keyPath: \.flareThreshold, range: 0.7...1)
                Param(model: model, title: "Länge", keyPath: \.flareLength, range: 0...1)
                Param(model: model, title: "Intensität", keyPath: \.flareIntensity, range: 0...1)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Farbe").gateCaption()
                    OptionStrip(items: FlareTint.allCases, selection: $model.settings.flareTint) { $0.title }
                }
                Hint("Nur kleine, sehr helle Lichtquellen erzeugen Streaks – helle Flächen wie weiße Wände bleiben unberührt. Schwelle höher = weniger Streaks, nur echte Lampen und Reflexe.")
            }
        }
        Group_(title: "Halation") {
            Param(model: model, title: "Warmer Hof", keyPath: \.halation, range: 0...1)
        }
    }
}

// MARK: - Farbe

private struct ColorPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        Group_(title: "Belichtung & Weißabgleich") {
            Param(model: model, title: "Belichtung", keyPath: \.exposure, range: -2...2, neutral: 0, format: Fmt.ev)
            Param(model: model, title: "Wärme", keyPath: \.warmth, range: -1...1, neutral: 0, format: Fmt.signedPercent)
            Param(model: model, title: "Tönung", keyPath: \.tint, range: -1...1, neutral: 0, format: Fmt.signedPercent)
        }
        Group_(title: "Ton") {
            Param(model: model, title: "Lichter", keyPath: \.highlights, range: -1...1, neutral: 0, format: Fmt.signedPercent)
            Param(model: model, title: "Tiefen", keyPath: \.shadows, range: -1...1, neutral: 0, format: Fmt.signedPercent)
            Param(model: model, title: "Kontrast", keyPath: \.contrast, range: -1...1, neutral: 0, format: Fmt.signedPercent)
            Param(model: model, title: "Sättigung", keyPath: \.saturation, range: -1...1, neutral: 0, format: Fmt.signedPercent)
        }
        Hint("Reihenfolge: Belichtung → Weißabgleich → Lichter/Tiefen → LUT → Kontrast/Sättigung. Die LUT sieht also das bereits korrigierte Bild.")
    }
}

// MARK: - Film

private struct FilmPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        Group_(title: "Korn") {
            Param(model: model, title: "Stärke", keyPath: \.grain, range: 0...1)
            Param(model: model, title: "Größe", keyPath: \.grainSize, range: 0...1)
        }
        Group_(title: "Vignette") {
            Param(model: model, title: "Stärke", keyPath: \.vignette, range: 0...1)
        }
    }
}

// MARK: - Untertitel

private struct TitlePanel: View {
    @Bindable var model: AppModel

    var body: some View {
        Group_(title: "Untertitel") {
            LampToggle(title: "Untertitel einblenden", isOn: $model.settings.subtitleEnabled)
            if model.settings.subtitleEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Text").gateCaption()
                    TextField("Was gesagt wird …", text: $model.settings.subtitleText, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.bg)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.hairline, lineWidth: 1))
                    Hint("Zeilenumbruch mit Return. Der Untertitel steht über dem fertigen Bild, nach Grading und Korn.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Stil").gateCaption()
                    OptionStrip(items: SubtitleStyle.allCases, selection: styleBinding) { $0.title }
                    if model.settings.subtitleStyle == .brat {
                        Hint("Schwarzer Kleinbuchstaben-Text auf #8ACE00, leicht verwaschen. Ein Stilwechsel setzt die dazu passende Schrift.")
                    }
                }

                Param(model: model, title: "Größe", keyPath: \.subtitleSize, range: 0...1)
                Param(model: model, title: "Höhe über Unterkante", keyPath: \.subtitlePosition, range: 0...0.4)
            }
        }

        if model.settings.subtitleEnabled {
            Group_(title: "Schrift") {
                VStack(spacing: 0) {
                    ForEach(SubtitleFont.allCases) { font in
                        let on = model.settings.subtitleFont == font
                        Button { model.settings.subtitleFont = font } label: {
                            HStack(spacing: 12) {
                                Rectangle().fill(on ? Theme.accent : Color.clear).frame(width: 2, height: 22)
                                Text(sample(font))
                                    .font(.custom(font.postScriptNames[0], size: 17))
                                    .foregroundStyle(on ? Theme.text : Theme.dim)
                                    .lineLimit(1)
                                Spacer()
                                Text(font.title).gateCaption(Theme.faint)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 1)
                    }
                }
            }
        }
    }

    private func sample(_ font: SubtitleFont) -> String {
        model.settings.subtitleStyle == .brat ? "so brat" : "I\u{2019}ll be back."
    }

    private var styleBinding: Binding<SubtitleStyle> {
        Binding(get: { model.settings.subtitleStyle },
                set: {
                    model.settings.subtitleStyle = $0
                    model.settings.subtitleFont = $0.defaultFont
                })
    }
}

// MARK: - Export

private struct ExportPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        Group_(title: "Ausgabe") {
            if let out = model.outputSize {
                row("Größe", "\(Int(out.width)) × \(Int(out.height))")
                row("Format", String(format: "%.2f : 1", out.width / out.height))
            }
            row("Farbraum", model.media == .video ? "SDR · Rec.709" : "Display P3")
            if model.media == .video {
                row("Codec", "HEVC · Ton unverändert")
            }
        }

        if model.media == .photo {
            Group_(title: "Dateiformat") {
                OptionStrip(items: AnamorphicRenderer.PhotoFormat.allCases, selection: $model.photoFormat) { $0.title }
            }
        }

        Group_(title: model.media == .video ? "Video rendern" : "Foto exportieren") {
            if model.isExporting {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.hairline)
                            Rectangle().fill(Theme.accent).frame(width: geo.size.width * model.exportProgress)
                        }
                    }
                    .frame(height: 3)
                    HStack {
                        Text(model.media == .video ? "Rendert …" : "Berechnet …").gateCaption()
                        Spacer()
                        Text(Fmt.percent(model.exportProgress) + " %").readout(Theme.accent, size: 11)
                    }
                    if model.media == .video {
                        Button("Abbrechen") { model.cancelExport() }
                            .buttonStyle(GateButtonStyle(kind: .secondary))
                    }
                }
            } else {
                Button(model.media == .video ? "Video rendern" : "Foto exportieren") { model.startExport() }
                    .buttonStyle(GateButtonStyle(kind: .primary))
                    .disabled(!model.hasMedia)
                    .keyboardShortcut("e")
            }

            if let url = model.exportedURL, !model.isExporting {
                HStack(spacing: 10) {
                    ShareLink(item: url) { Text("Teilen / Sichern") }
                        .buttonStyle(GateButtonStyle(kind: .secondary))
                    Button("In Fotos") { Task { await model.saveToPhotos() } }
                        .buttonStyle(GateButtonStyle(kind: .secondary))
                }
            }
            if let notice = model.notice {
                Text(notice).readout(Theme.accent, size: 11)
            }
            if model.media == .video {
                Hint("Das Rendern läuft auf der GPU. Ein 4K-Clip braucht je nach Gerät grob das 1–4-fache seiner Länge. Das Display bitte währenddessen nicht sperren.")
            }
        }

        Group_(title: "Zurücksetzen") {
            Button("Alle Regler auf Standard") {
                let lut = model.settings.lutSpace
                model.settings = AnamorphicSettings()
                model.settings.lutSpace = lut
            }
            .buttonStyle(GateButtonStyle(kind: .quiet))
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).gateCaption()
            Spacer()
            Text(value).readout(Theme.text, size: 12)
        }
    }
}
