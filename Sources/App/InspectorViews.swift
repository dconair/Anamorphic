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
                .id(model.tab)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animation(.easeOut(duration: 0.22), value: model.tab)
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
        if let analysis = model.analysis {
            Group_(title: "Bildanalyse", trailing: model.isAnalyzing ? "…" : nil) {
                AnalysisCard(analysis: analysis, pulse: model.analysisPulse)
                Button("Neu analysieren") { model.reanalyze() }
                    .buttonStyle(GateButtonStyle(kind: .secondary))
            }
        }

        Group_(title: "Voreinstellung", trailing: model.suggestions.isEmpty ? nil : "nach Eignung") {
            VStack(spacing: 0) {
                ForEach(orderedPresets) { item in
                    PresetRow(preset: item.preset,
                              score: item.score,
                              reason: item.reason,
                              selected: model.activePreset == item.preset) {
                        model.apply(preset: item.preset)
                    }
                }
            }
            .animation(.snappy(duration: 0.35), value: model.suggestions.map(\.id))
            Hint("Die Reihenfolge richtet sich nach dem Bild: Helligkeit, Farbtemperatur, Lichtquellen und Gesichter. Ein Preset ist nur ein Startpunkt, alles bleibt einstellbar.")
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

    private struct Ranked: Identifiable { let preset: StylePreset; let score: Double; let reason: String; var id: String { preset.id } }

    private var orderedPresets: [Ranked] {
        var list = model.suggestions.map { Ranked(preset: $0.preset, score: $0.score, reason: $0.reason) }
        for p in StylePreset.allCases where !list.contains(where: { $0.preset == p }) {
            list.append(Ranked(preset: p, score: model.suggestions.isEmpty ? 0 : -1, reason: p.summary))
        }
        return list
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

// MARK: - Analyse-Karte und Preset-Zeile

private struct PresetRow: View {
    let preset: StylePreset
    let score: Double          // < 0 = nicht bewertet
    let reason: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Rectangle().fill(selected ? Theme.accent : Color.clear).frame(width: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.title).font(Theme.serif(15))
                            .foregroundStyle(selected ? Theme.text : Theme.text.opacity(0.85))
                        Text(score >= 0.5 ? reason : preset.summary)
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if score >= 0 {
                        MatchBar(value: score, highlighted: score >= 0.5)
                    }
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 1)
        }
    }
}

/// Fünf Striche wie eine Pegelanzeige – so viele leuchten, wie das Preset zum Bild passt.
private struct MatchBar: View {
    let value: Double
    let highlighted: Bool
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Rectangle()
                    .fill(Double(i) < value * 5 - 0.2
                          ? (highlighted ? Theme.accent : Theme.dim)
                          : Theme.hairline)
                    .frame(width: 3, height: 11)
            }
        }
        .animation(.easeOut(duration: 0.5), value: value)
        .accessibilityLabel("Eignung \(Int(value * 100)) Prozent")
    }
}

private struct AnalysisCard: View {
    let analysis: ImageAnalysis
    let pulse: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Meter(title: "Helligkeit", value: analysis.meanLuma)
            Meter(title: "Kontrast", value: analysis.contrast)
            Meter(title: "Wärme", value: 0.5 + analysis.warmth * 2.5, centered: true)
            Meter(title: "Farbsättigung", value: analysis.saturation)
            HStack {
                Text("Lichtquellen").gateCaption()
                Spacer()
                Text(analysis.hasLightSources ? "\(analysis.lightSourceCount)" : "keine")
                    .font(Theme.mono(11)).foregroundStyle(Theme.text)
            }
            HStack {
                Text("Gesichter").gateCaption()
                Spacer()
                Text(analysis.faceCount == 0 ? "keine" : "\(analysis.faceCount)")
                    .font(Theme.mono(11)).foregroundStyle(Theme.text)
            }
        }
        .padding(12)
        .background(Theme.bg)
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
        .id(pulse)
        .transition(.opacity)
    }
}

private struct Meter: View {
    let title: String
    let value: Double
    var centered = false
    @State private var shown = 0.0

    var body: some View {
        HStack(spacing: 10) {
            Text(title).gateCaption().frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.hairline).frame(height: 2)
                    if centered {
                        let c = geo.size.width / 2
                        let x = geo.size.width * shown
                        Rectangle().fill(Theme.accent)
                            .frame(width: abs(x - c), height: 2)
                            .offset(x: min(x, c))
                    } else {
                        Rectangle().fill(Theme.accent).frame(width: geo.size.width * shown, height: 2)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 12)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { shown = value.clamped(0, 1) } }
        .onChange(of: value) { _, v in withAnimation(.easeOut(duration: 0.7)) { shown = v.clamped(0, 1) } }
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
        }

        Group_(title: "Anamorphot") {
            Param(model: model, title: "Linsen-Squeeze", keyPath: \.squeeze, range: 1...2, format: Fmt.factor)
            Param(model: model, title: "Breitenstreckung", keyPath: \.desqueeze, range: 1...1.6, format: Fmt.factor)
            Param(model: model, title: "Randdehnung", keyPath: \.edgeStretch, range: 0...1)
            Param(model: model, title: "Randunschärfe", keyPath: \.edgeSoftness, range: 0...1)
            Hint("Wie bei einer echten Anamorphot-Aufnahme: Unschärfe, Flares und Korn entstehen im gequetschten Bild und werden danach mit dem Faktor der Breitenstreckung wieder auseinandergezogen. Daher sind Bokeh-Scheiben oval. Der Linsen-Squeeze bestimmt die Ovalität (1.5× ≈ 1.5:1). Randdehnung streckt die Bildränder stärker als die Mitte (leichter Weitwinkel-„Mumps“-Effekt), Randunschärfe macht die Ränder weicher. Für Material, das schon anamorph gefilmt wurde, Streckung auf den Adapter-Faktor stellen (z. B. 1.33×).")
        }

        Group_(title: "Bokeh") {
            LampToggle(title: "Anamorphes Bokeh", isOn: $model.settings.bokehEnabled)
            if model.settings.bokehEnabled {
                Param(model: model, title: "Unschärfe", keyPath: \.bokehAmount, range: 0...1)
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
