import Foundation

enum CubeLUTError: LocalizedError, Equatable {
    case unsupported1D
    case missingSize
    case invalidLine(Int)
    case wrongCount(expected: Int, got: Int)

    var errorDescription: String? {
        switch self {
        case .unsupported1D:
            return "1D-LUTs werden nicht unterstützt. Bitte eine 3D-LUT (.cube mit LUT_3D_SIZE) verwenden."
        case .missingSize:
            return "In der .cube-Datei fehlt LUT_3D_SIZE."
        case .invalidLine(let n):
            return "Ungültige Zeile \(n) in der .cube-Datei."
        case .wrongCount(let expected, let got):
            return "Die LUT enthält \(got) statt \(expected) Einträge."
        }
    }
}

/// 3D-LUT im Adobe/Resolve-.cube-Format. Die Reihenfolge der Daten ist
/// "Rot am schnellsten", genau wie bei `CIColorCube`.
struct CubeLUT: Equatable, @unchecked Sendable {
    let title: String
    let size: Int
    /// size³ × 3 Werte (R,G,B), normalisiert auf 0…1.
    let rgb: [Float]
    /// Vorberechnete RGBA-Float32-Daten für Core Image (nicht pro Frame neu bauen!).
    let cubeData: Data

    init(title: String, size: Int, rgb: [Float]) {
        self.title = title
        self.size = size
        self.rgb = rgb

        var rgba = [Float]()
        rgba.reserveCapacity(size * size * size * 4)
        var i = 0
        while i + 2 < rgb.count {
            rgba.append(rgb[i])
            rgba.append(rgb[i + 1])
            rgba.append(rgb[i + 2])
            rgba.append(1)
            i += 3
        }
        self.cubeData = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func == (lhs: CubeLUT, rhs: CubeLUT) -> Bool {
        lhs.title == rhs.title && lhs.size == rhs.size && lhs.rgb == rhs.rgb
    }

    // MARK: Parsen

    static func parse(_ text: String, fallbackTitle: String = "LUT") throws -> CubeLUT {
        var title = fallbackTitle
        var size = 0
        var dMin: [Float] = [0, 0, 0]
        var dMax: [Float] = [1, 1, 1]
        var values = [Float]()

        var lineNo = 0
        for rawLine in text.split(whereSeparator: \.isNewline) {
            lineNo += 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let first = parts.first else { continue }

            switch first {
            case "TITLE":
                let t = line.dropFirst("TITLE".count).trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
                if !t.isEmpty { title = t }
            case "LUT_3D_SIZE":
                guard parts.count >= 2, let n = Int(parts[1]), n >= 2, n <= 129 else { throw CubeLUTError.invalidLine(lineNo) }
                size = n
                values.reserveCapacity(n * n * n * 3)
            case "LUT_1D_SIZE":
                throw CubeLUTError.unsupported1D
            case "DOMAIN_MIN":
                guard parts.count >= 4, let a = Float(parts[1]), let b = Float(parts[2]), let c = Float(parts[3]) else { throw CubeLUTError.invalidLine(lineNo) }
                dMin = [a, b, c]
            case "DOMAIN_MAX":
                guard parts.count >= 4, let a = Float(parts[1]), let b = Float(parts[2]), let c = Float(parts[3]) else { throw CubeLUTError.invalidLine(lineNo) }
                dMax = [a, b, c]
            default:
                if let f = first.first, f.isNumber || f == "-" || f == "+" || f == "." {
                    guard parts.count >= 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) else {
                        throw CubeLUTError.invalidLine(lineNo)
                    }
                    values.append(contentsOf: [r, g, b])
                }
                // Unbekannte Schlüsselwörter (z. B. LUT_IN_VIDEO_RANGE) werden ignoriert.
            }
        }

        guard size > 0 else { throw CubeLUTError.missingSize }
        let expected = size * size * size * 3
        guard values.count == expected else {
            throw CubeLUTError.wrongCount(expected: expected / 3, got: values.count / 3)
        }

        // Auf 0…1 normalisieren, falls eine abweichende Domain angegeben ist.
        if dMin != [0, 0, 0] || dMax != [1, 1, 1] {
            for i in 0..<values.count {
                let c = i % 3
                let range = dMax[c] - dMin[c]
                if range > 0 { values[i] = (values[i] - dMin[c]) / range }
            }
        }
        return CubeLUT(title: title, size: size, rgb: values)
    }

    // MARK: Erzeugen / Schreiben

    static func generate(title: String, size: Int = 33,
                         transform: (Float, Float, Float) -> (Float, Float, Float)) -> CubeLUT {
        var out = [Float]()
        out.reserveCapacity(size * size * size * 3)
        let d = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let t = transform(Float(r) / d, Float(g) / d, Float(b) / d)
                    out.append(t.0)
                    out.append(t.1)
                    out.append(t.2)
                }
            }
        }
        return CubeLUT(title: title, size: size, rgb: out)
    }

    /// .cube-Text, z. B. um einen eingebauten Look in DaVinci Resolve zu verwenden.
    func cubeString() -> String {
        var s = "TITLE \"\(title)\"\nLUT_3D_SIZE \(size)\nDOMAIN_MIN 0.0 0.0 0.0\nDOMAIN_MAX 1.0 1.0 1.0\n"
        var i = 0
        while i + 2 < rgb.count {
            s += String(format: "%.6f %.6f %.6f\n", rgb[i], rgb[i + 1], rgb[i + 2])
            i += 3
        }
        return s
    }
}
