import Foundation

/// Schreibt die ORF-Musikaufstellung (Vorlage „ORF_AKMliste_Vorlage.xlsx“).
/// Zellpositionen aus der Analyse der vom Nutzer gelieferten Vorlage (Stand 11/2026).
enum AKMExport {
    static let firstDataRow = 15
    static let lastTemplateRow = 63      // 49 vorformatierte Zeilen; mehr werden unten angehängt
    static let sheetName = "Musikaufstellung"

    static func templateURL() -> URL? {
        if let u = Bundle.main.url(forResource: "ORF_AKMliste_Vorlage", withExtension: "xlsx") { return u }
        // Entwicklung: neben dem Programm / im Projektordner
        let candidates = [
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("ORF_AKMliste_Vorlage.xlsx"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/ORF_AKMliste_Vorlage.xlsx"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// - progress: (erledigt, gesamt, Beschreibung)
    static func write(works: [MusicWork], rate: FrameRate, produktion p: Produktionsdaten, to out: URL,
                      progress: (Int, Int, String) -> Void = { _, _, _ in }) throws {
        guard let tpl = templateURL() else { throw XLSXError.structure("ORF-Vorlage nicht gefunden") }
        let total = works.count + 3
        progress(0, total, "Vorlage öffnen")
        let x = try XLSXTemplate(template: tpl)

        progress(1, total, "Kopfdaten eintragen")
        let head: [(String, String)] = [
            ("AS1", p.verfasserCode), ("AS2", p.nummer),
            ("H3", p.produktionsnummer), ("U3", p.folgenummer),
            ("H4", p.sendetitel), ("H5", p.untertitel),
            ("H7", p.regie), ("H8", p.redaktion), ("H9", p.regieassistenz),
            ("K11", p.fuerRichtigkeit), ("K12", p.firma), ("AH12", p.telefon),
            ("AR4", p.sendedatum1), ("AR5", p.sendezeit1Von), ("AU5", p.sendezeit1Bis),
            ("AR7", p.sendedatum2), ("AR8", p.sendezeit2Von), ("AU8", p.sendezeit2Bis),
            ("AR10", p.sendebereich),
            ("AD3", p.aufzeichnung ? "x" : ""), ("AD4", p.aufzeichnung ? "" : "x"),
        ]
        for (ref, v) in head { try x.setString(ref, v) }

        for (i, w) in works.enumerated() {
            let r = firstDataRow + i
            if r > lastTemplateRow { try x.cloneRow(from: lastTemplateRow, to: r) }
            progress(2 + i, total, "Zeile \(i + 1) von \(works.count): \(w.titel)")
            let sec = w.seconds(rate: rate)
            try x.setString("A\(r)", w.beitrag)
            try x.setString("G\(r)", w.titel)
            try x.setString("M\(r)", w.interpret)
            try x.setString("S\(r)", w.komponist)
            try x.setString("Y\(r)", w.bearbeiter)
            try x.setString("AE\(r)", w.autor)
            try x.setString("AK\(r)", w.verlag)
            try x.setString("AQ\(r)", w.musikvideo ? "x" : "")
            try x.setString("AR\(r)", w.live ? "x" : "")
            try x.setNumber("AS\(r)", sec >= 60 ? Double(sec / 60) : nil)
            try x.setNumber("AU\(r)", Double(sec % 60))
        }
        let lastRow = max(lastTemplateRow, firstDataRow + works.count - 1)
        try x.setPrintLayout(titleRows: 14...14, sheetName: sheetName)
        progress(total - 1, total, "Datei speichern")
        try x.save(to: out)
        _ = lastRow
        progress(total, total, "Fertig")
    }
}
