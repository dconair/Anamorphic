# Anamorphic

Native SwiftUI-App für **iPhone, iPad und Mac**. Sie macht aus normalen Fotos und Videos Aufnahmen mit
anamorphem Kino-Look: 2.39:1-Zuschnitt, ovales Bokeh, horizontale Streak-Flares, Color Grading mit
**.cube-LUTs**, Korn, Vignette und optional Untertitel im Streaming- oder Brat-Stil.
Alles ist einstellbar – nichts läuft nur automatisch.

> **Stand:** Der Code wurde ohne Mac geschrieben. Syntax aller Swift-Dateien ist geprüft (Swift 6.0.3),
> die reine Logik (Bildformat-Berechnung, .cube-Parser, Looks, JSON) wurde ausgeführt und ist grün.
> Core Image, AVFoundation, Vision und die UI wurden **nicht** in Xcode gebaut oder auf einem Gerät getestet.
> Rechne beim ersten Build mit ein paar kleinen Compilerfehlern und mit Feintuning der Flare-Stärke
> (siehe unten).

## Bauen (5 Minuten)

Voraussetzung: Mac mit **Xcode 16+**, iOS 17 / macOS 14 als Mindestsystem.

```bash
brew install xcodegen
cd Anamorphic
xcodegen generate
open Anamorphic.xcodeproj
```

1. In `project.yml` `bundleIdPrefix`, die Bundle-IDs und `DEVELOPMENT_TEAM` anpassen (oder in Xcode unter *Signing & Capabilities* ein Team wählen).
2. Schema **Anamorphic-iOS** (iPhone/Simulator) oder **Anamorphic-macOS** wählen, ⌘R.
3. Kern-Tests (läuft ohne Simulator): `swift test` im Projektordner.

Ohne XcodeGen: In Xcode ein neues *Multiplatform → App* anlegen, die Ordner `Sources/Core` und `Sources/App`
hineinziehen, Mindestversionen iOS 17 / macOS 14 setzen und die Fotos-Berechtigungen aus `project.yml`
(`NSPhotoLibrary…`) sowie auf dem Mac die Sandbox-Rechte *User Selected File (Read/Write)* und *Photos Library*
eintragen.

## DMG und IPA in einem Schritt

```bash
bash scripts/build-release.sh
```

Das Skript erzeugt `Ergebnisse/Anamorphic.dmg` (ad-hoc signiert, beim ersten Start Rechtsklick → Öffnen) und
`Ergebnisse/Anamorphic.ipa` (unsigniert; mit AltStore oder Sideloadly und deiner Apple-ID signieren und aufs iPhone laden,
kostenloser Account = 7 Tage Gültigkeit). Dieselben Schritte laufen als GitHub-Action (`.github/workflows/build.yml`),
sobald das Projekt in einem GitHub-Repo liegt – dann kommen DMG und IPA als Download-Artefakt.

## Bedienung

- **Mediathek / Datei / Drag & Drop** öffnet Foto oder Video. Eine `.cube`-Datei kann ebenfalls hineingezogen werden.
- **Bild gedrückt halten** zeigt das Original (Vorher/Nachher).
- Regler: Doppeltipp setzt auf Standard zurück.
- Reiter: **Look** (Voreinstellungen, eingebaute Looks, LUT-Import) · **Linse** (Format, Bokeh, Farbsäume) ·
  **Flare** · **Farbe** · **Film** (Korn, Vignette) · **Titel** (Untertitel) · **Export**.
- Video: Der Schieberegler unter dem Bild wählt das Vorschau-Bild. Der Export rendert das ganze Video auf der GPU, Ton bleibt erhalten.

## Wie der Look entsteht (und warum er nicht "gezerrt" aussieht)

Die Pipeline (`Sources/Core/Renderer.swift`) folgt dem Weg des Lichts:

1. **Bokeh** – Unschärfe wird im horizontal gestauchten Raum gerechnet und danach wieder gestreckt. So
   werden Unschärfescheiben oval wie bei einer echten Anamorphot-Linse, ohne dass das Bild selbst verzerrt wird.
   Motive werden per Vision erkannt und bleiben scharf (Foto); im Video wirkt eine einstellbare Ellipse.
2. **Laterale Farbsäume** – R/B-Kanäle leicht gegeneinander skaliert, null in der Mitte, stärker zum Rand.
3. **Streak-Flares + Halation** – nur kleine, sehr helle Lichtquellen streuen (Top-Hat-Filter schließt weiße
   Wände aus). Horizontale Streaks in wählbarer Farbe (Blau, Bernstein, Neutral, Magenta), dazu ein warmer Hof.
4. **Zuschnitt** auf 2.39 / 2.35 / 2.00 / 1.85 – immer ein **Ausschnitt, keine Streckung**. Maße sind gerade
   Pixelzahlen (Video-Encoder). *Desqueeze* ist standardmäßig 1.00× und nur für Material gedacht, das wirklich
   mit einem Anamorphot-Vorsatz gedreht wurde.
5. **Farbe** – Belichtung → Weißabgleich → Lichter/Tiefen → **LUT** (Stärke regelbar) → Kontrast/Sättigung.
6. **Vignette, Korn** (Korngröße relativ zur Bildbreite, pro Videoframe neu gewürfelt).
7. **Untertitel** – CoreText-Ebene über dem fertigen Bild: *Kino* (weiß, weicher Schatten), *Klassisch*
   (gelb mit Kontur) oder *Brat* (kleingeschrieben, schwarz auf #8ACE00, leicht verwaschen); sechs Schriften.
   Im Video steht der Untertitel über die gesamte Länge (keine Zeitsteuerung in v0.1).

Alle Pixelgrößen sind relativ zur Bildbreite, Vorschau und Export sehen deshalb gleich aus.

### Farbmanagement

- Core Image rechnet linear im erweiterten Arbeitsfarbraum. Die LUT wird in dem Farbraum angewendet, den du
  im Look-Reiter wählst (Rec.709 / sRGB / Display P3) – die Umrechnung übernimmt Core Image.
- Fotos werden als Display P3 geschrieben (JPEG / HEIC / PNG). Videos kommen als SDR Rec.709 (HEVC) heraus;
  HDR-Material (HLG / Dolby Vision) rechnet AVFoundation dabei nach SDR um.
- Die eingebauten Looks sind parametrische Rezepte (`Looks.swift`), die beim Start in echte 33³-LUTs gebacken werden.
  Es liegen keine Binär-Assets im Projekt.

### Ehrlich eingeordnet

- Ein **1.33×-Vorsatz** auf dem iPhone liefert in der Realität breiteres Bild, Verzerrung und horizontale
  Flares, aber **kein** ovales Bokeh. Ovales Bokeh gehört zu echten Cinema-Anamorphoten (1.6×–2×). Die App
  simuliert beides getrennt, damit du entscheiden kannst, welchen Look du willst (*Ovalität* 1.0 = rund).
- Aus einem normalen 16:9-Clip lässt sich kein breiteres Sichtfeld herstellen – der 2.39-Look ist ein Zuschnitt.

## Feintuning

Alle Konstanten, die den Charakter bestimmen, stehen in `Renderer.Tuning` (Bokeh-Radius, Streak-Länge/-Helligkeit,
Aberration). Wenn Flares auf dem Gerät zu schwach oder zu hell wirken, ist `streakClamp` bzw. der Faktor `0.45`
in `streakLayer` die erste Stellschraube. Eigene Looks: Rezepte in `Looks.swift` ergänzen.

## Bekannte Grenzen von v0.1

- Untertitel haben keine Zeitsteuerung / SRT-Import.
- Videovorschau zeigt Einzelbilder (Scrubbing), kein Live-Abspielen mit Effekten.
- Motiv-Maske nur für Fotos (im Video Ellipse).
- Apple-Log-Video wird nicht gesondert behandelt; dafür Apples Log→Rec.709-LUT importieren und Look auf „Kein Look“ stellen.
- Kein App-Icon.

## Struktur

```
Sources/Core   Bild-Pipeline ohne UI (auch per `swift test` testbar)
  Settings.swift      alle Parameter, Formatgeometrie, Voreinstellungen
  Renderer.swift      Core-Image-Pipeline
  Looks.swift         eingebaute Looks → 3D-LUT
  CubeLUT.swift       .cube lesen/schreiben
  Subtitles.swift     Untertitel (CoreText)
  SubjectMask.swift   Motiverkennung (Vision)
  VideoExporter.swift AVFoundation-Export
Sources/App    SwiftUI (iOS + macOS aus einer Codebasis)
Tests          Kern-Tests
project.yml    XcodeGen-Definition
```
