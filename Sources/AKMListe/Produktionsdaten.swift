import Foundation

/// Kopfdaten einer Produktion – gemeinsam für alle FuFF-Tools (Datei-Endung .fuffprod, JSON).
/// Jedes Tool liest und schreibt dieselbe Datei; unbekannte Felder bleiben beim Speichern erhalten.
struct Produktionsdaten: Codable, Equatable {
    var sendetitel = ""
    var untertitel = ""
    var produktionsnummer = ""
    var folgenummer = ""
    var materialnummer = ""
    var produktionsart = ""           // Eigen-/Auftrags-/Koproduktion
    var produzent = ""
    var regie = ""
    var regieassistenz = ""
    var autor = ""
    var sprecher = ""
    var redaktion = ""
    var sendungsverantwortlich = ""   // S-Verantwortl./Redakteur
    var fuerRichtigkeit = ""          // Für die Richtigkeit des Inhalts
    var abteilung = ""
    var firma = ""
    var telefon = ""
    var verfasserCode = ""
    var nummer = ""
    var aufzeichnung = true           // Aufzeichnung (sonst Live)
    var sendedatum1 = ""
    var sendezeit1Von = ""
    var sendezeit1Bis = ""
    var sendedatum2 = ""
    var sendezeit2Von = ""
    var sendezeit2Bis = ""
    var sendebereich = ""
    var extra: [String: String]? = nil  // Felder anderer FuFF-Tools, unverändert durchgereicht

    static let fileExtension = "fuffprod"
    private static let defaultsKey = "letzteProduktionsdaten"

    static func load(from url: URL) throws -> Produktionsdaten {
        try JSONDecoder().decode(Produktionsdaten.self, from: Data(contentsOf: url))
    }

    func save(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    static func lastUsed() -> Produktionsdaten {
        guard let d = UserDefaults.standard.data(forKey: defaultsKey),
              let p = try? JSONDecoder().decode(Produktionsdaten.self, from: d) else { return Produktionsdaten() }
        return p
    }

    func rememberAsLastUsed() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.defaultsKey) }
    }
}
