import Foundation

/// Gespeicherte AKM-Liste (Datei-Endung .fuffakm, JSON).
/// Enthält die EDL(s) selbst – die Datei funktioniert also auch, wenn die EDL verschoben wurde.
struct AKMProjekt: Codable {
    var format = "FuFF AKM-Liste"
    var version = 1
    var gespeichert = Date()
    var edls: [EDLDatei]
    var bildrate: String
    var musikspuren: [String]
    var werke: [MusicWork]
    var produktion: Produktionsdaten

    static let fileExtension = "fuffakm"

    struct EDLDatei: Codable {
        var name: String
        var pfad: String
        var inhalt: String
    }

    func save(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(self).write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> AKMProjekt {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(AKMProjekt.self, from: Data(contentsOf: url))
    }

    /// Eingebettete EDLs als Dateien in einen eigenen Temp-Ordner schreiben (Originalnamen bleiben erhalten).
    func materializeEDLs() throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fuffakm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try edls.map { e in
            let safe = e.name.replacingOccurrences(of: "/", with: "_")
            let u = dir.appendingPathComponent(safe.isEmpty ? "Schnitt.edl" : safe)
            try e.inhalt.write(to: u, atomically: true, encoding: .utf8)
            return u
        }
    }
}

extension Produktionsdaten {
    /// Für einen neuen Film: nur Firmenangaben übernehmen, alles Filmbezogene leer.
    var nurFirma: Produktionsdaten {
        var p = Produktionsdaten()
        p.firma = firma
        p.telefon = telefon
        p.verfasserCode = verfasserCode
        p.abteilung = abteilung
        return p
    }
}
