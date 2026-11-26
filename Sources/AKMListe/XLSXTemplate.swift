import Foundation

enum XLSXError: LocalizedError {
    case tool(String)
    case structure(String)
    var errorDescription: String? {
        switch self {
        case .tool(let s): return "Excel-Datei konnte nicht verarbeitet werden: \(s)"
        case .structure(let s): return "Vorlage hat einen unerwarteten Aufbau: \(s)"
        }
    }
}

/// Füllt eine vorhandene .xlsx-Vorlage, ohne ihre Formatierung anzufassen:
/// entpacken (ditto) → Tabellen-XML gezielt ändern → wieder packen (zip).
/// Texte werden als „inline strings“ geschrieben, die gemeinsame Textliste der Vorlage bleibt unverändert.
final class XLSXTemplate {
    private let dir: URL
    private let sheetURL: URL
    private let workbookURL: URL
    private let doc: XMLDocument
    private var root: XMLElement { doc.rootElement()! }

    init(template: URL) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("akm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.run("/usr/bin/ditto", ["-x", "-k", template.path, dir.path])
        sheetURL = dir.appendingPathComponent("xl/worksheets/sheet1.xml")
        workbookURL = dir.appendingPathComponent("xl/workbook.xml")
        guard FileManager.default.fileExists(atPath: sheetURL.path) else { throw XLSXError.structure("Blatt 1 fehlt") }
        doc = try XMLDocument(contentsOf: sheetURL, options: [.nodePreserveAll])
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    // MARK: Zellen

    static func split(_ ref: String) -> (col: String, row: Int) {
        let letters = ref.prefix { $0.isLetter }
        return (String(letters), Int(ref.dropFirst(letters.count)) ?? 0)
    }

    static func colIndex(_ col: String) -> Int {
        col.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
    }

    private var sheetData: XMLElement {
        get throws {
            guard let sd = root.kids("sheetData").first else { throw XLSXError.structure("sheetData fehlt") }
            return sd
        }
    }

    private func row(_ r: Int, create: Bool = true) throws -> XMLElement? {
        let sd = try sheetData
        let rows = sd.kids("row")
        if let found = rows.first(where: { $0.attribute(forName: "r")?.stringValue == String(r) }) { return found }
        guard create else { return nil }
        let el = XMLElement(name: "row")
        el.addAttribute(XMLNode.attribute(withName: "r", stringValue: String(r)) as! XMLNode)
        let idx = rows.firstIndex { (Int($0.attribute(forName: "r")?.stringValue ?? "") ?? 0) > r }
        if let i = idx, let pos = sd.children?.firstIndex(where: { $0 === rows[i] }) {
            sd.insertChild(el, at: pos)
        } else {
            sd.addChild(el)
        }
        return el
    }

    private func cell(_ ref: String) throws -> XMLElement {
        let (col, r) = Self.split(ref)
        guard let rowEl = try row(r) else { throw XLSXError.structure("Zeile \(r)") }
        let cells = rowEl.kids("c")
        if let c = cells.first(where: { $0.attribute(forName: "r")?.stringValue == ref }) { return c }
        let el = XMLElement(name: "c")
        el.addAttribute(XMLNode.attribute(withName: "r", stringValue: ref) as! XMLNode)
        let ci = Self.colIndex(col)
        if let next = cells.first(where: { Self.colIndex(Self.split($0.attribute(forName: "r")?.stringValue ?? "A").col) > ci }),
           let pos = rowEl.children?.firstIndex(where: { $0 === next }) {
            rowEl.insertChild(el, at: pos)
        } else {
            rowEl.addChild(el)
        }
        return el
    }

    private func clear(_ c: XMLElement) {
        c.setChildren(nil)
        c.removeAttribute(forName: "t")
    }

    func setString(_ ref: String, _ value: String) throws {
        let c = try cell(ref)
        clear(c)
        guard !value.isEmpty else { return }
        c.addAttribute(XMLNode.attribute(withName: "t", stringValue: "inlineStr") as! XMLNode)
        let t = XMLElement(name: "t", stringValue: value)
        t.addAttribute(XMLNode.attribute(withName: "xml:space", stringValue: "preserve") as! XMLNode)
        let isEl = XMLElement(name: "is")
        isEl.addChild(t)
        c.addChild(isEl)
    }

    func setNumber(_ ref: String, _ value: Double?) throws {
        let c = try cell(ref)
        clear(c)
        guard let v = value else { return }
        let s = v == v.rounded() ? String(Int(v)) : String(v)
        c.addChild(XMLElement(name: "v", stringValue: s))
    }

    // MARK: Zeilen anhängen (mehr Einträge als Vorlagenzeilen)

    /// Legt Zeile `target` als Kopie von Zeile `source` an – mit Zellformaten, Höhe und verbundenen Zellen.
    func cloneRow(from source: Int, to target: Int) throws {
        guard let src = try row(source, create: false) else { throw XLSXError.structure("Musterzeile \(source) fehlt") }
        if try row(target, create: false) != nil { return }
        let copy = src.copy() as! XMLElement
        copy.attribute(forName: "r")?.stringValue = String(target)
        for c in copy.kids("c") {
            let (col, _) = Self.split(c.attribute(forName: "r")?.stringValue ?? "A")
            c.attribute(forName: "r")?.stringValue = "\(col)\(target)"
            clear(c)
        }
        let sd = try sheetData
        let rows = sd.kids("row")
        if let next = rows.first(where: { (Int($0.attribute(forName: "r")?.stringValue ?? "") ?? 0) > target }),
           let pos = sd.children?.firstIndex(where: { $0 === next }) {
            sd.insertChild(copy, at: pos)
        } else {
            sd.addChild(copy)
        }
        if let mc = root.kids("mergeCells").first {
            for m in mc.kids("mergeCell") {
                guard let ref = m.attribute(forName: "ref")?.stringValue else { continue }
                let parts = ref.split(separator: ":").map(String.init)
                guard parts.count == 2 else { continue }
                let a = Self.split(parts[0]), b = Self.split(parts[1])
                if a.row == source && b.row == source {
                    let n = XMLElement(name: "mergeCell")
                    n.addAttribute(XMLNode.attribute(withName: "ref", stringValue: "\(a.col)\(target):\(b.col)\(target)") as! XMLNode)
                    mc.addChild(n)
                }
            }
            mc.attribute(forName: "count")?.stringValue = String(mc.kids("mergeCell").count)
        }
        if let dim = root.kids("dimension").first, let ref = dim.attribute(forName: "ref")?.stringValue {
            let parts = ref.split(separator: ":").map(String.init)
            if parts.count == 2 {
                let b = Self.split(parts[1])
                if target > b.row { dim.attribute(forName: "ref")?.stringValue = "\(parts[0]):\(b.col)\(target)" }
            }
        }
    }

    // MARK: Druck

    /// Querformat, auf Seitenbreite skalieren, Kopfzeile(n) der Tabelle auf jeder Seite wiederholen.
    func setPrintLayout(titleRows: ClosedRange<Int>, sheetName: String) throws {
        var sheetPr = root.kids("sheetPr").first
        if sheetPr == nil {
            let el = XMLElement(name: "sheetPr")
            root.insertChild(el, at: 0)
            sheetPr = el
        }
        let pr = sheetPr!.kids("pageSetUpPr").first ?? {
            let el = XMLElement(name: "pageSetUpPr")
            sheetPr!.addChild(el)
            return el
        }()
        pr.removeAttribute(forName: "fitToPage")
        pr.addAttribute(XMLNode.attribute(withName: "fitToPage", stringValue: "1") as! XMLNode)
        if let ps = root.kids("pageSetup").first {
            for (k, v) in [("orientation", "landscape"), ("fitToWidth", "1"), ("fitToHeight", "0"), ("paperSize", "9")] {
                ps.removeAttribute(forName: k)
                ps.addAttribute(XMLNode.attribute(withName: k, stringValue: v) as! XMLNode)
            }
        }
        // Wiederholungszeilen über definierten Namen in workbook.xml
        let wb = try XMLDocument(contentsOf: workbookURL, options: [.nodePreserveAll])
        guard let wroot = wb.rootElement() else { return }
        let dn = wroot.kids("definedNames").first ?? {
            let el = XMLElement(name: "definedNames")
            if let sheets = wroot.kids("sheets").first,
               let pos = wroot.children?.firstIndex(where: { $0 === sheets }) {
                wroot.insertChild(el, at: pos + 1)
            } else {
                wroot.addChild(el)
            }
            return el
        }()
        for old in dn.kids("definedName") where old.attribute(forName: "name")?.stringValue == "_xlnm.Print_Titles" {
            old.detach()
        }
        let def = XMLElement(name: "definedName", stringValue: "'\(sheetName)'!$\(titleRows.lowerBound):$\(titleRows.upperBound)")
        def.addAttribute(XMLNode.attribute(withName: "name", stringValue: "_xlnm.Print_Titles") as! XMLNode)
        def.addAttribute(XMLNode.attribute(withName: "localSheetId", stringValue: "0") as! XMLNode)
        dn.addChild(def)
        try wb.xmlData(options: [.nodePreserveAll]).write(to: workbookURL)
    }

    // MARK: Speichern

    func save(to out: URL) throws {
        try doc.xmlData(options: [.nodePreserveAll]).write(to: sheetURL)
        let tmpZip = dir.deletingLastPathComponent().appendingPathComponent("akm-\(UUID().uuidString).xlsx")
        let entries = (try FileManager.default.contentsOfDirectory(atPath: dir.path))
            .sorted { a, b in a == "[Content_Types].xml" ? true : (b == "[Content_Types].xml" ? false : a < b) }
        try Self.run("/usr/bin/zip", ["-X", "-r", "-q", tmpZip.path] + entries, cwd: dir)
        if FileManager.default.fileExists(atPath: out.path) { try FileManager.default.removeItem(at: out) }
        try FileManager.default.moveItem(at: tmpZip, to: out)
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String], cwd: URL? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard p.terminationStatus == 0 else { throw XLSXError.tool("\(tool) – \(out.prefix(300))") }
        return out
    }
}

extension XMLElement {
    /// Kindelemente nach lokalem Namen (unabhängig vom Standard-Namensraum der OOXML-Dateien).
    func kids(_ name: String) -> [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }.filter { ($0.localName ?? $0.name) == name }
    }
}
