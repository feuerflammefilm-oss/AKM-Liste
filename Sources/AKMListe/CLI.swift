import Foundation

/// Kommandozeilenmodus (für den automatischen Test beim Bauen):
/// AKMListe --cli --edl a.edl [--edl b.edl] --tracks A5,A6 [--rate 25] [--produktion p.fuffprod] --out liste.xlsx
enum CLI {
    /// Suchtest gegen MusicBrainz (beim Bauen): Exit 0 = Treffer, 3 = kein Treffer, 4 = Netzwerkfehler.
    static func searchTest(_ text: String) -> Never {
        setvbuf(stdout, nil, _IONBF, 0)
        var w = MusicWork(key: text)
        w.titel = text
        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Task.detached {
            do {
                let r = try await MusicBrainz.shared.search(w)
                print("Suche: \(MusicBrainz.searchTerms(for: w).joined(separator: " / "))\(r.relaxed ? " (locker)" : "")")
                for c in r.candidates.prefix(5) { print("  \(c.score)  \(c.titel) – \(c.interpret) · \(c.album)") }
                if let first = r.candidates.first {
                    let d = try await MusicBrainz.shared.details(first)
                    print("  Details: \(d.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "))")
                }
                code = r.candidates.isEmpty ? 3 : 0
            } catch {
                print("Netzwerk/Server: \(error.localizedDescription)")
                code = 4
            }
            sem.signal()
        }
        sem.wait()
        exit(code)
    }

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--suche"), i + 1 < args.count { searchTest(args[i + 1]) }
        guard args.contains("--cli") else { return false }
        setvbuf(stdout, nil, _IONBF, 0)     // Ausgabe sofort (sonst geht sie bei einem Absturz verloren)
        var edls: [URL] = []
        var tracks: Set<String> = []
        var rate = FrameRate.standard
        var out: URL?
        var prod = Produktionsdaten()
        var exclude: Set<String> = []
        var remove: Set<String> = []
        var saveTo: URL?
        var projectIn: URL?
        var i = 1
        func next() -> String? { i += 1; return i < args.count ? args[i] : nil }
        while i < args.count {
            switch args[i] {
            case "--edl": if let v = next() { edls.append(URL(fileURLWithPath: v)) }
            case "--tracks": if let v = next() { tracks = Set(v.split(separator: ",").map(String.init)) }
            case "--rate": if let v = next(), let r = FrameRate.byLabel(v) { rate = r }
            case "--out": if let v = next() { out = URL(fileURLWithPath: v) }
            case "--ausschliessen": if let v = next() { exclude.insert(v) }
            case "--loeschen": if let v = next() { remove.insert(v) }
            case "--speichern": if let v = next() { saveTo = URL(fileURLWithPath: v) }
            case "--projekt": if let v = next() { projectIn = URL(fileURLWithPath: v) }
            case "--produktion":
                if let v = next() {
                    do { prod = try Produktionsdaten.load(from: URL(fileURLWithPath: v)) }
                    catch { print("Hinweis: Produktionsdaten nicht lesbar (\(v)): \(error)") }
                }
            default: break
            }
            i += 1
        }
        do {
            var previous: [String: MusicWork] = [:]
            if let pin = projectIn {
                let p = try AKMProjekt.load(from: pin)
                edls = try p.materializeEDLs()
                tracks = Set(p.musikspuren)
                if let r = FrameRate.byLabel(p.bildrate) { rate = r }
                prod = p.produktion
                previous = Dictionary(p.werke.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
                print("Projekt geladen: \(pin.lastPathComponent) (\(p.werke.count) Werke)")
            }
            guard let out, !edls.isEmpty else {
                FileHandle.standardError.write(Data("Aufruf: --cli --edl DATEI --tracks A1,A2 --out LISTE.xlsx\n".utf8))
                exit(2)
            }
            var events: [EDLEvent] = []
            for (n, u) in edls.enumerated() {
                let f = try EDLParser.parse(u, rate: rate, trackPrefix: edls.count > 1 ? "\(n + 1)·" : "")
                f.warnings.forEach { print("Hinweis: \($0)") }
                events += f.events
            }
            if tracks.isEmpty { tracks = MusicAnalysis.suggestedMusicTracks(events) }
            var works = MusicAnalysis.works(from: events, musicTracks: tracks, rate: rate, previous: previous)
            for i in works.indices where exclude.contains(works[i].key) { works[i].ausschliessen = true }
            for i in works.indices where remove.contains(works[i].key) { works[i].geloescht = true }
            for w in works {
                print("\(MusicAnalysis.mmss(w.seconds(rate: rate)))\t\(w.uses)×\t\(w.titel)\t\(w.komponist)\(w.ausschliessen ? "\t(ausgeschlossen)" : "")\(w.geloescht ? "\t(gelöscht)" : "")")
            }
            if let saveTo {
                let p = AKMProjekt(edls: try edls.map { u in
                    AKMProjekt.EDLDatei(name: u.lastPathComponent, pfad: u.path, inhalt: try EDLParser.readText(u))
                }, bildrate: rate.label, musikspuren: tracks.sorted(), werke: works, produktion: prod)
                try p.save(to: saveTo)
                print("Gesichert: \(saveTo.lastPathComponent)")
            }
            try AKMExport.write(works: works.filter { !$0.ausschliessen && !$0.geloescht }, rate: rate, produktion: prod, to: out) { done, total, what in
                print("[\(done)/\(total)] \(what)")
            }
            print("OK \(works.count) Werke → \(out.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("FEHLER: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
