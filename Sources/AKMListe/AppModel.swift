import AppKit
import Foundation
import SwiftUI

struct BusyState: Equatable {
    var title: String
    var detail: String = ""
    var done: Int = 0
    var total: Int = 1
    var finishedURL: URL? = nil
    var error: String? = nil
    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var edls: [EDLFile] = []
    @Published var rate: FrameRate = .standard { didSet { if oldValue != rate { reparse() } } }
    @Published var audioTracks: [String] = []
    @Published var trackExamples: [String: [String]] = [:]
    @Published var musicTracks: Set<String> = [] { didSet { recompute() } }
    @Published var works: [MusicWork] = []
    @Published var produktion = Produktionsdaten.lastUsed() { didSet { produktion.rememberAsLastUsed() } }
    @Published var selection: MusicWork.ID?
    @Published var candidates: [String: [ResearchCandidate]] = [:]
    @Published var researchLog: [ResearchLog] = []
    @Published var searchStatus: [String: String] = [:]   // Rückmeldung je Werk
    @Published var searching: Set<String> = []
    @Published var busy: BusyState?
    @Published var showTrackSheet = false
    @Published var showProduktion = false
    private var cancelRequested = false
    private var saved: [String: MusicWork] = [:]

    var warnings: [String] { edls.flatMap { f in f.warnings.map { "\(f.url.lastPathComponent): \($0)" } } }
    var openCount: Int { works.filter { !$0.offen.isEmpty }.count }
    var excludedCount: Int { works.filter(\.ausschliessen).count }

    // MARK: EDL laden

    func open(_ urls: [URL]) {
        let edlURLs = urls.filter { ["edl", "txt"].contains($0.pathExtension.lowercased()) }
        guard !edlURLs.isEmpty else { return }
        let all = Array(Set(edls.map(\.url) + edlURLs)).sorted { $0.lastPathComponent < $1.lastPathComponent }
        if edls.isEmpty, let first = all.first { rate = EDLParser.suggestedRate(first) }
        loadSaved(for: all)
        parse(all)
        let suggested = MusicAnalysis.suggestedMusicTracks(edls.flatMap(\.events))
        musicTracks = suggested
        showTrackSheet = true
    }

    func closeAll() {
        persist()
        edls = []; works = []; audioTracks = []; musicTracks = []; candidates = [:]; researchLog = []; selection = nil
    }

    private func parse(_ urls: [URL]) {
        var files: [EDLFile] = []
        for (n, u) in urls.enumerated() {
            let prefix = urls.count > 1 ? "\(u.deletingPathExtension().lastPathComponent) · " : ""
            do { files.append(try EDLParser.parse(u, rate: rate, trackPrefix: prefix)) }
            catch { var f = EDLFile(url: u); f.warnings = ["Datei nicht lesbar: \(error.localizedDescription)"]; files.append(f) }
            _ = n
        }
        edls = files
        let events = files.flatMap(\.events)
        var ex: [String: [String]] = [:]
        for e in events where !e.track.hasSuffix("V") {
            var l = ex[e.track, default: []]
            if l.count < 3 && !l.contains(e.clipName) && !e.clipName.isEmpty { l.append(e.clipName) }
            ex[e.track] = l
        }
        trackExamples = ex
        audioTracks = ex.keys.sorted { a, b in a.localizedStandardCompare(b) == .orderedAscending }
        recompute()
    }

    private func reparse() { if !edls.isEmpty { parse(edls.map(\.url)) } }

    func recompute() {
        for w in works { saved[w.key] = w }
        works = MusicAnalysis.works(from: edls.flatMap(\.events), musicTracks: musicTracks, rate: rate, previous: saved)
        persist()
    }

    func binding(for key: String) -> Binding<MusicWork>? {
        guard works.contains(where: { $0.key == key }) else { return nil }
        return Binding(
            get: { self.works.first { $0.key == key } ?? MusicWork(key: key) },
            set: { new in
                guard let i = self.works.firstIndex(where: { $0.key == key }) else { return }
                var w = new
                for f in ["beitrag", "titel", "interpret", "komponist", "bearbeiter", "autor", "verlag"]
                where Self.value(w, f) != Self.value(self.works[i], f) { w.quellen[f] = "Nutzer" }
                self.works[i] = w
                self.persist()
            })
    }

    static func value(_ w: MusicWork, _ f: String) -> String {
        switch f {
        case "beitrag": return w.beitrag
        case "titel": return w.titel
        case "interpret": return w.interpret
        case "komponist": return w.komponist
        case "bearbeiter": return w.bearbeiter
        case "autor": return w.autor
        default: return w.verlag
        }
    }

    // MARK: Automatisch speichern (Eingaben bleiben je EDL erhalten)

    private func storeURL(for urls: [URL]) -> URL {
        let key = urls.map(\.path).sorted().joined(separator: "|")
        var h: UInt64 = 5381
        for b in key.utf8 { h = (h &* 33) ^ UInt64(b) }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FuFF AKM-Liste", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(String(h, radix: 16) + ".json")
    }

    private func loadSaved(for urls: [URL]) {
        if let d = try? Data(contentsOf: storeURL(for: urls)),
           let list = try? JSONDecoder().decode([MusicWork].self, from: d) {
            saved = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        } else {
            saved = [:]
        }
    }

    func persist() {
        guard !edls.isEmpty else { return }
        for w in works { saved[w.key] = w }
        if let d = try? JSONEncoder().encode(Array(saved.values)) { try? d.write(to: storeURL(for: edls.map(\.url))) }
    }

    // MARK: Recherche

    /// Online-Recherche nur für veröffentlichte Musik: Bibliotheksmusik (UPM …) steht nicht in MusicBrainz.
    var researchTargets: [MusicWork] {
        works.filter { !$0.ausschliessen && $0.bibliothek.isEmpty && ($0.komponist.isEmpty || $0.verlag.isEmpty) }
    }
    var exportWorks: [MusicWork] { works.filter { !$0.ausschliessen } }

    func researchAll() {
        let targets = researchTargets
        guard !targets.isEmpty else { return }
        cancelRequested = false
        busy = BusyState(title: "Musik recherchieren (MusicBrainz)", total: targets.count)
        Task {
            for (n, w) in targets.enumerated() {
                if cancelRequested { break }
                busy?.done = n
                busy?.detail = "\(n + 1) von \(targets.count): \(w.titel)"
                await runSearch(w)
                if let c = candidates[w.key], c.count == 1, !(searchStatus[w.key] ?? "").contains("locker") {
                    await choose(c[0], for: w.key, quiet: true)
                    searchStatus[w.key] = "1 Treffer übernommen (MusicBrainz) – bitte prüfen."
                }
                if (searchStatus[w.key] ?? "").hasPrefix("Fehler: Keine Verbindung") {
                    busy?.error = searchStatus[w.key]
                    break
                }
            }
            busy?.done = targets.count
            busy?.detail = "Fertig – Werke mit mehreren Treffern: Auswahl rechts in der Detailansicht"
            if busy?.error == nil { busy = nil }
        }
    }

    func researchOne(_ key: String) {
        guard let w = works.first(where: { $0.key == key }), !searching.contains(key) else { return }
        searching.insert(key)
        searchStatus[key] = "Suche läuft …"
        Task {
            defer { searching.remove(key) }
            await runSearch(w)
        }
    }

    /// Eine Suche mit sichtbarer Rückmeldung (Treffer / kein Treffer / Fehler im Klartext).
    private func runSearch(_ w: MusicWork) async {
        let terms = MusicBrainz.searchTerms(for: w).joined(separator: " / ")
        do {
            let r = try await MusicBrainz.shared.search(w)
            researchLog.append(ResearchLog(url: r.url, anfrage: terms,
                                           ergebnis: "\(r.candidates.count) Treffer\(r.relaxed ? " (lockere Suche)" : "")"))
            candidates[w.key] = r.candidates
            switch r.candidates.count {
            case 0:
                searchStatus[w.key] = "Kein Treffer für „\(terms)“. Tipp: Titel oder Interpret oben korrigieren und erneut suchen."
            case 1:
                searchStatus[w.key] = "1 Treffer gefunden\(r.relaxed ? " (lockere Suche – bitte prüfen)" : "")."
            default:
                searchStatus[w.key] = "\(r.candidates.count) mögliche Treffer\(r.relaxed ? " (lockere Suche)" : "") – bitte die passende Aufnahme wählen."
            }
        } catch {
            researchLog.append(ResearchLog(url: "", anfrage: terms, ergebnis: error.localizedDescription))
            searchStatus[w.key] = "Fehler: \(error.localizedDescription)"
        }
    }

    func cancelBusy() { cancelRequested = true; if busy?.error != nil || busy?.finishedURL != nil { busy = nil } }

    func choose(_ c: ResearchCandidate, for key: String, quiet: Bool = false) async {
        guard works.contains(where: { $0.key == key }) else { return }
        func put(_ f: String, _ v: String) {
            // Index jedes Mal neu suchen: die Liste kann sich während der Netzwerkabfrage ändern
            guard !v.isEmpty, let i = works.firstIndex(where: { $0.key == key }) else { return }
            var w = works[i]
            // Nutzereingaben werden nie überschrieben
            if w.quellen[f] == "Nutzer" && !Self.value(w, f).isEmpty { return }
            switch f {
            case "titel": w.titel = v
            case "interpret": w.interpret = v
            case "beitrag": w.beitrag = v
            case "komponist": w.komponist = v
            case "autor": w.autor = v
            case "bearbeiter": w.bearbeiter = v
            default: w.verlag = v
            }
            w.quellen[f] = "MusicBrainz"
            works[i] = w
        }
        put("titel", c.titel); put("interpret", c.interpret); put("beitrag", c.album)
        do {
            let d = try await MusicBrainz.shared.details(c)
            researchLog.append(contentsOf: d.log)
            for (k, v) in d.fields { put(k, v) }
        } catch {
            researchLog.append(ResearchLog(url: "", anfrage: c.titel, ergebnis: error.localizedDescription))
        }
        candidates[key] = nil
        if let w = works.first(where: { $0.key == key }) {
            let got = [("Komponist", w.komponist), ("Verlag/Label", w.verlag), ("Album", w.beitrag)]
                .filter { !$0.1.isEmpty }.map(\.0)
            searchStatus[key] = "Übernommen von MusicBrainz: Titel, Interpret" + (got.isEmpty ? "" : ", " + got.joined(separator: ", "))
                + (w.komponist.isEmpty ? ". Komponist ist dort nicht eingetragen – bitte selbst ergänzen." : ". Bitte prüfen.")
        }
        persist()
    }

    // MARK: Export

    func export(to url: URL) {
        let works = self.exportWorks, rate = self.rate, prod = self.produktion
        busy = BusyState(title: "AKM-Liste exportieren", total: works.count + 3)
        Task.detached(priority: .userInitiated) {
            do {
                try AKMExport.write(works: works, rate: rate, produktion: prod, to: url) { done, total, what in
                    Task { @MainActor in
                        self.busy?.done = done; self.busy?.total = total; self.busy?.detail = what
                    }
                }
                await MainActor.run { self.busy?.finishedURL = url; self.busy?.detail = "Gespeichert: \(url.lastPathComponent)" }
            } catch {
                await MainActor.run { self.busy?.error = error.localizedDescription }
            }
        }
    }
}
