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


    enum CodingKeys: String, CodingKey, CaseIterable {
        case sendetitel, untertitel, produktionsnummer, folgenummer, materialnummer, produktionsart, produzent, regie, regieassistenz, autor, sprecher, redaktion, sendungsverantwortlich, fuerRichtigkeit, abteilung, firma, telefon, verfasserCode, nummer, sendedatum1, sendezeit1Von, sendezeit1Bis, sendedatum2, sendezeit2Von, sendezeit2Bis, sendebereich, aufzeichnung, extra
    }

    init() {}

    /// Tolerantes Einlesen: fehlende Felder bleiben leer (Dateien anderer FuFF-Tools haben evtl. weniger Felder);
    /// unbekannte Textfelder landen in `extra` und werden beim Speichern wieder mitgeschrieben.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sendetitel = try c.decodeIfPresent(String.self, forKey: .sendetitel) ?? ""
        untertitel = try c.decodeIfPresent(String.self, forKey: .untertitel) ?? ""
        produktionsnummer = try c.decodeIfPresent(String.self, forKey: .produktionsnummer) ?? ""
        folgenummer = try c.decodeIfPresent(String.self, forKey: .folgenummer) ?? ""
        materialnummer = try c.decodeIfPresent(String.self, forKey: .materialnummer) ?? ""
        produktionsart = try c.decodeIfPresent(String.self, forKey: .produktionsart) ?? ""
        produzent = try c.decodeIfPresent(String.self, forKey: .produzent) ?? ""
        regie = try c.decodeIfPresent(String.self, forKey: .regie) ?? ""
        regieassistenz = try c.decodeIfPresent(String.self, forKey: .regieassistenz) ?? ""
        autor = try c.decodeIfPresent(String.self, forKey: .autor) ?? ""
        sprecher = try c.decodeIfPresent(String.self, forKey: .sprecher) ?? ""
        redaktion = try c.decodeIfPresent(String.self, forKey: .redaktion) ?? ""
        sendungsverantwortlich = try c.decodeIfPresent(String.self, forKey: .sendungsverantwortlich) ?? ""
        fuerRichtigkeit = try c.decodeIfPresent(String.self, forKey: .fuerRichtigkeit) ?? ""
        abteilung = try c.decodeIfPresent(String.self, forKey: .abteilung) ?? ""
        firma = try c.decodeIfPresent(String.self, forKey: .firma) ?? ""
        telefon = try c.decodeIfPresent(String.self, forKey: .telefon) ?? ""
        verfasserCode = try c.decodeIfPresent(String.self, forKey: .verfasserCode) ?? ""
        nummer = try c.decodeIfPresent(String.self, forKey: .nummer) ?? ""
        sendedatum1 = try c.decodeIfPresent(String.self, forKey: .sendedatum1) ?? ""
        sendezeit1Von = try c.decodeIfPresent(String.self, forKey: .sendezeit1Von) ?? ""
        sendezeit1Bis = try c.decodeIfPresent(String.self, forKey: .sendezeit1Bis) ?? ""
        sendedatum2 = try c.decodeIfPresent(String.self, forKey: .sendedatum2) ?? ""
        sendezeit2Von = try c.decodeIfPresent(String.self, forKey: .sendezeit2Von) ?? ""
        sendezeit2Bis = try c.decodeIfPresent(String.self, forKey: .sendezeit2Bis) ?? ""
        sendebereich = try c.decodeIfPresent(String.self, forKey: .sendebereich) ?? ""
        aufzeichnung = try c.decodeIfPresent(Bool.self, forKey: .aufzeichnung) ?? true
        var ex = try c.decodeIfPresent([String: String].self, forKey: .extra) ?? [:]
        let any = try decoder.container(keyedBy: AnyKey.self)
        let known: Set<String> = ["sendetitel", "untertitel", "produktionsnummer", "folgenummer", "materialnummer", "produktionsart", "produzent", "regie", "regieassistenz", "autor", "sprecher", "redaktion", "sendungsverantwortlich", "fuerRichtigkeit", "abteilung", "firma", "telefon", "verfasserCode", "nummer", "sendedatum1", "sendezeit1Von", "sendezeit1Bis", "sendedatum2", "sendezeit2Von", "sendezeit2Bis", "sendebereich", "aufzeichnung", "extra"]
        for k in any.allKeys where !known.contains(k.stringValue) {
            if let v = try? any.decode(String.self, forKey: k) { ex[k.stringValue] = v }
        }
        extra = ex.isEmpty ? nil : ex
    }

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

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
