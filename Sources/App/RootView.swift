import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: AppModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showLUTImporter = false

    var body: some View {
        let accent = Theme.accent   // hier lesen: Palettenwechsel aktualisiert die ganze Oberfläche
        return GeometryReader { geo in
            let wide = geo.size.width >= 820
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    TopBar(model: model, pickerItem: $pickerItem, openFile: { showFileImporter = true })
                    DottedLine()
                    if wide {
                        HStack(spacing: 0) {
                            CanvasView(model: model, openFile: { showFileImporter = true })
                            Rectangle().fill(Theme.hairline).frame(width: 1)
                            InspectorView(model: model, importLUT: { showLUTImporter = true })
                                .frame(width: 360)
                        }
                    } else {
                        VStack(spacing: 0) {
                            CanvasView(model: model, openFile: { showFileImporter = true })
                                .frame(height: max(220, geo.size.height * 0.38))
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                            InspectorView(model: model, importLUT: { showLUTImporter = true })
                        }
                    }
                }
            }
        }
        .tint(accent)
        .onChange(of: model.settings) { model.scheduleRender() }
        .onChange(of: model.customLUT) { model.scheduleRender() }
        .onChange(of: model.videoTime) { model.videoTimeChanged() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                await model.load(pickerItem: item)
                pickerItem = nil
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .movie], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await model.open(fileURL: url) }
            }
        }
        .fileImporter(isPresented: $showLUTImporter,
                      allowedContentTypes: [UTType(filenameExtension: "cube") ?? .plainText, .plainText, .data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.importLUT(url: url)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            if url.pathExtension.lowercased() == "cube" {
                model.importLUT(url: url)
            } else {
                Task { await model.open(fileURL: url) }
            }
            return true
        }
        .alert("Hinweis", isPresented: Binding(get: { model.errorMessage != nil },
                                              set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Obere Leiste

private struct TopBar: View {
    @Bindable var model: AppModel
    @Binding var pickerItem: PhotosPickerItem?
    let openFile: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    DotText(text: "ANAMORPHIC", dot: 2.6, color: Theme.text)
                    LED(on: model.hasMedia, color: model.isExporting ? Theme.accent : Theme.secondary)
                }
                if model.hasMedia {
                    Text(model.sourceName).gateCaption(Theme.faint).lineLimit(1)
                }
            }
            Spacer(minLength: 8)

            PaletteButton()

            PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                Text("Mediathek")
            }
            .buttonStyle(GateButtonStyle(kind: .secondary))

            Button("Datei", action: openFile)
                .buttonStyle(GateButtonStyle(kind: model.hasMedia ? .secondary : .primary))
                .keyboardShortcut("o")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.bg)
    }
}

// MARK: - Leinwand

private struct CanvasView: View {
    @Bindable var model: AppModel
    let openFile: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.bg
                DotGrid()
                if model.hasMedia {
                    preview
                } else {
                    EmptyGate(openFile: openFile)
                }
            }
            if model.hasMedia {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ReadoutBar(model: model)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        let shown = (model.showOriginal ? model.originalImage : model.previewImage) ?? model.previewImage
        VStack(spacing: 10) {
            if let player = model.player {
                PlayerLayerView(player: player)
                    .aspectRatio(max(0.1, model.liveOutputSize.width) / max(0.1, model.liveOutputSize.height), contentMode: .fit)
                    .overlay { ViewfinderMarks().padding(-9) }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let shown {
                Image(decorative: shown, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        if model.showOriginal {
                            Text("Original")
                                .gateCaption(Theme.bg)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.accent)
                                .padding(8)
                        }
                    }
                    .overlay { ViewfinderMarks().padding(-9) }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    // Gedrückt halten = Original zeigen. Die lange Dauer sorgt dafür, dass nur
                    // der Press-Callback feuert, nie die Aktion selbst.
                    .onLongPressGesture(minimumDuration: 60, maximumDistance: 60, perform: {}, onPressingChanged: { pressing in
                        model.showOriginal = pressing
                    })
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if model.media == .video {
                HStack(spacing: 10) {
                    Button(model.isPlaying ? "Pause" : (model.liveActive ? "Weiter" : "Abspielen")) { model.togglePlay() }
                        .buttonStyle(GateButtonStyle(kind: .secondary))
                        .keyboardShortcut(.space, modifiers: [])
                    if model.liveActive {
                        Button("Standbild") { model.stopLive() }
                            .buttonStyle(GateButtonStyle(kind: .secondary))
                    }
                    Spacer()
                    Text(model.liveActive ? "Live-Vorschau, max. 1280 px" : "Einzelbild")
                        .gateCaption(Theme.faint)
                }
                .padding(.horizontal, 20)
                ScaleSlider(title: "Position", value: $model.videoTime,
                            range: 0...max(0.1, model.videoDuration), format: Fmt.time)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct EmptyGate: View {
    let openFile: () -> Void

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Rectangle().fill(Theme.panel.opacity(0.9))
                Rectangle().stroke(Theme.hairline, lineWidth: 1)
                ViewfinderMarks(length: 18).padding(-6)
                DotText(text: "2.39:1", dot: 5, color: Theme.text, unlit: Color(red: 0.10, green: 0.10, blue: 0.11))
            }
            .aspectRatio(2.39, contentMode: .fit)
            .frame(maxWidth: 380)

            VStack(spacing: 8) {
                Text("Foto oder Video öffnen")
                    .font(Theme.serif(20))
                    .foregroundStyle(Theme.text)
                Text("Aus der Mediathek, als Datei oder per Drag & Drop.\nEine .cube-LUT kannst du ebenfalls hineinziehen.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.dim)
            }
            Button("Datei öffnen", action: openFile)
                .buttonStyle(GateButtonStyle(kind: .primary))
        }
        .padding(24)
    }
}

private struct ReadoutBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 22) {
            if let out = model.outputSize {
                cell("Format", String(format: "%.2f:1", out.width / out.height))
                cell("Ausgabe", "\(Int(out.width))×\(Int(out.height))")
            }
            cell("Look", lookName)
            Spacer(minLength: 0)
            Text("Gedrückt halten: Original").gateCaption(Theme.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Theme.bg)
    }

    private var lookName: String {
        if model.settings.lookID == "custom" { return model.customLUT?.title ?? "LUT" }
        return LookLibrary.look(id: model.settings.lookID)?.title ?? "–"
    }

    private func cell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).gateCaption(Theme.faint)
            Text(value).readout(Theme.text, size: 12).lineLimit(1)
        }
    }
}
