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

## Wie der Look entsteht

Kurzfassung: Die App spielt den Weg einer anamorphen Aufnahme rückwärts nach – *Squeeze → Optik → Desqueeze*.
Die ausführliche Erklärung mit Optik-Hintergrund steht in [`docs/ANAMORPHIC-PHYSIK.md`](docs/ANAMORPHIC-PHYSIK.md).

Die Pipeline (`Sources/Core/Renderer.swift`):

1. **Bildanalyse** (`ImageAnalysis.swift`) – Helligkeit, Kontrast, Farbtemperatur, Lichtquellen, Kantendichte und Gesichter
   werden gemessen. Daraus werden Presets nach Eignung sortiert; das beste wird automatisch gesetzt und an das Bild
   angepasst (keine Flares ohne echte Lichtquelle, Gesichter werden kaum gedehnt, ohnehin weiche Bilder bekommen weniger Bokeh).
2. **Im Sensorraum** (horizontal um den Linsen-Squeeze gestaucht): Bokeh-Unschärfe, Randunschärfe. Danach wird wieder
   gestreckt, so werden die Scheiben oval.
3. **Laterale Farbsäume** – R/B-Kanäle leicht gegeneinander skaliert, null in der Mitte, stärker zum Rand.
4. **Streak-Flares + Halation** – nur kleine, sehr helle Lichtquellen des *Originalbildes* streuen (Top-Hat-Filter schließt
   weiße Wände aus). Horizontale Streaks in wählbarer Farbe, dazu ein warmer ovaler Hof.
5. **Streifenweise Streckung** (`Stretch.swift`) – die Breite wird um die „Breitenstreckung“ gedehnt, der Rand stärker als
   die Mitte (Randdehnung, wie beim echten Anamorphoten). Die mittlere Streckung bleibt exakt der eingestellte Wert.
6. **Zuschnitt** auf 2.39 / 2.35 / 2.00 / 1.85, gerade Pixelmaße (Video-Encoder).
7. **Farbe** – Belichtung → Weißabgleich → Lichter/Tiefen → **LUT** (Stärke regelbar) → Kontrast/Sättigung.
8. **Ovale Vignette, Korn** (Korn horizontal gestreckt wie das Bild, relativ zur Bildbreite, pro Videoframe neu).
9. **Untertitel** – CoreText-Ebene: *Kino*, *Klassisch*, *Brat*; sechs Schriften.

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
  simuliert beides getrennt: *Linsen-Squeeze* 1.0 = rundes Bokeh.
- Aus einem normalen 16:9-Clip lässt sich kein echtes zusätzliches Sichtfeld herstellen. Die App dehnt das Bild
  deshalb nur mäßig (Standard 1.2×, Rand stärker) und schneidet auf 2.39 zu; ein Rest ist immer Zuschnitt.

## Feintuning

Alle Konstanten, die den Charakter bestimmen, stehen in `Renderer.Tuning` (Bokeh-Radius, Streak-Länge/-Helligkeit,
Aberration, Korn). Wenn Flares oder Korn zu schwach oder zu stark wirken, sind `streakGain`, `streakClamp` und
`grainAmplitude` die ersten Stellschrauben. Eigene Looks: Rezepte in `Looks.swift` ergänzen.

## Bekannte Grenzen von v0.1

- Untertitel haben keine Zeitsteuerung / SRT-Import.
- Videovorschau zeigt Einzelbilder (Scrubbing), kein Live-Abspielen mit Effekten.
- Motiv-Maske nur für Fotos (im Video Ellipse).
- Apple-Log-Video wird nicht gesondert behandelt; dafür Apples Log→Rec.709-LUT importieren und Look auf „Kein Look“ stellen.

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
