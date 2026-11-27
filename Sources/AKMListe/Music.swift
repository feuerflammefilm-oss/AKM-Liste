import Foundation

/// Ein Musikwerk/eine Aufnahme mit allen Einsätzen im Film.
/// Für die ORF-AKM-Liste zählt nur die GESAMTDAUER: mehrere Einsätze werden zusammengerechnet.
/// Gerechnet wird die Vereinigung der Zeitbereiche – Stereo-Doppelungen (gleicher Clip auf zwei Spuren)
/// und Überlappungen werden so nicht doppelt gezählt.
struct MusicWork: Identifiable, Codable, Hashable {
    var id: String { key }
    var key: String                 // normalisierter Clipname (stabil, für Speicherung)
    var clipNames: [String] = []
    var firstFrame: Int = 0
    var totalFrames: Int = 0
    var uses: Int = 0               // getrennte Einsätze (Lücke > 0,5 s)
    var tracks: [String] = []

    // Felder der AKM-Liste
    var beitrag = ""                // Beitrag / Album
    var titel = ""
    var interpret = ""
    var komponist = ""
    var bearbeiter = ""
    var autor = ""
    var verlag = ""                 // Verlag / Schallplatte (Label)
    var musikvideo = false
    var live = false
    var quellen: [String: String] = [:]   // Feld -> Herkunft der Angabe ("Dateiname", "MusicBrainz", "Nutzer")
    var ausschliessen = false       // z. B. Geräusche, Originalton-Gesang: nicht in die AKM-Liste
    var bibliothek = ""             // Production-Music-Bibliothek (z. B. Universal Production Music)
    var trackID = ""                // Track-ID der Bibliothek aus dem Dateinamen

    init(key: String) { self.key = key }

    enum CodingKeys: String, CodingKey {
        case key, clipNames, firstFrame, totalFrames, uses, tracks, beitrag, titel, interpret, komponist, bearbeiter,
             autor, verlag, musikvideo, live, quellen, ausschliessen, bibliothek, trackID
    }

    /// Tolerant: gespeicherte Eingaben älterer Versionen (ohne neue Felder) bleiben lesbar.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        clipNames = try c.decodeIfPresent([String].self, forKey: .clipNames) ?? []
        firstFrame = try c.decodeIfPresent(Int.self, forKey: .firstFrame) ?? 0
        totalFrames = try c.decodeIfPresent(Int.self, forKey: .totalFrames) ?? 0
        uses = try c.decodeIfPresent(Int.self, forKey: .uses) ?? 0
        tracks = try c.decodeIfPresent([String].self, forKey: .tracks) ?? []
        beitrag = try c.decodeIfPresent(String.self, forKey: .beitrag) ?? ""
        titel = try c.decodeIfPresent(String.self, forKey: .titel) ?? ""
        interpret = try c.decodeIfPresent(String.self, forKey: .interpret) ?? ""
        komponist = try c.decodeIfPresent(String.self, forKey: .komponist) ?? ""
        bearbeiter = try c.decodeIfPresent(String.self, forKey: .bearbeiter) ?? ""
        autor = try c.decodeIfPresent(String.self, forKey: .autor) ?? ""
        verlag = try c.decodeIfPresent(String.self, forKey: .verlag) ?? ""
        musikvideo = try c.decodeIfPresent(Bool.self, forKey: .musikvideo) ?? false
        live = try c.decodeIfPresent(Bool.self, forKey: .live) ?? false
        quellen = try c.decodeIfPresent([String: String].self, forKey: .quellen) ?? [:]
        ausschliessen = try c.decodeIfPresent(Bool.self, forKey: .ausschliessen) ?? false
        bibliothek = try c.decodeIfPresent(String.self, forKey: .bibliothek) ?? ""
        trackID = try c.decodeIfPresent(String.self, forKey: .trackID) ?? ""
    }

    func seconds(rate: FrameRate) -> Int { Int((Double(totalFrames) / rate.fps).rounded()) }
    var offen: [String] {
        if ausschliessen { return [] }
        var o: [String] = []
        if komponist.isEmpty { o.append("Komponist") }
        else if (quellen["komponist"] ?? "").hasPrefix("Dateiname") { o.append("Komponist prüfen") }
        if verlag.isEmpty { o.append("Verlag") }
        if quellen["titel"] == "Dateiname" { o.append("Titel prüfen") }
        return o
    }
}

enum MusicAnalysis {
    private static let audioExt: Set<String> = ["wav", "aif", "aiff", "mp3", "m4a", "flac", "aac", "bwf", "mxf", "mov", "ogg"]
    private static let channelSuffix = try! NSRegularExpression(
        pattern: #"([ ._-](L|R|LEFT|RIGHT|A\d|CH\d|\d{1,2}CH)|\s*\((STEREO|MONO|L|R)\))$"#, options: [.caseInsensitive])

    /// Avid-Kopien/Subclips: „.COPY.01“, „.NEW.01“, „.SYNC.01“ … (auch mehrfach, z. B. „.WAV.COPY.01“)
    private static let avidSuffix = try! NSRegularExpression(
        pattern: #"\.(COPY|NEW|SYNC|SUB|MC|DUP|EXPORTED)(\.\d+)?$"#, options: [.caseInsensitive])

    static func key(for clip: String) -> String {
        var name = clip.trimmingCharacters(in: .whitespaces)
        var before = ""
        while before != name {               // Avid-Endungen und Dateiendungen abwechselnd entfernen
            before = name
            let ns = name as NSString
            name = avidSuffix.stringByReplacingMatches(in: name, range: NSRange(location: 0, length: ns.length),
                                                       withTemplate: "").trimmingCharacters(in: .whitespaces)
            let ext = (name as NSString).pathExtension.lowercased()
            if audioExt.contains(ext) { name = (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces) }
        }
        var prev = ""
        while prev != name {
            prev = name
            let ns = name as NSString
            name = channelSuffix.stringByReplacingMatches(in: name, range: NSRange(location: 0, length: ns.length),
                                                          withTemplate: "").trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? "(ohne Name)" : name
    }

    /// Suchtext aus dem Dateinamen – Rollen (Interpret/Titel/Komponist) werden NICHT geraten.
    static func titleSuggestion(_ key: String) -> String {
        var s = key.replacingOccurrences(of: "_", with: " ")
        if let r = s.range(of: #"^\d{1,3}\s*[.\-]*\s*-?\s+"#, options: .regularExpression) { s.removeSubrange(r) }
        return s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// Spuren, deren Clips überwiegend Audiodateien sind, als Musik vorschlagen.
    static func suggestedMusicTracks(_ events: [EDLEvent]) -> Set<String> {
        var stats: [String: (audio: Int, all: Int)] = [:]
        for e in events where !e.track.hasSuffix("V") {
            let ext = (e.clipName as NSString).pathExtension.lowercased()
            var st = stats[e.track] ?? (0, 0)
            st.all += 1
            if audioExt.contains(ext) && ext != "mov" && ext != "mxf" { st.audio += 1 }
            stats[e.track] = st
        }
        return Set(stats.filter { $0.value.all > 0 && Double($0.value.audio) / Double($0.value.all) >= 0.5 }.map(\.key))
    }

    static func works(from events: [EDLEvent], musicTracks: Set<String>, rate: FrameRate,
                      previous: [String: MusicWork] = [:]) -> [MusicWork] {
        var groups: [String: [EDLEvent]] = [:]
        for e in events where musicTracks.contains(e.track) && e.duration > 0 {
            groups[key(for: e.clipName.isEmpty ? e.reel : e.clipName), default: []].append(e)
        }
        let gapFrames = Int(0.5 * rate.fps)
        var result: [MusicWork] = []
        for (k, evs) in groups {
            let iv = evs.map { ($0.recordIn, $0.recordOut) }.sorted { $0.0 < $1.0 }
            var merged: [(Int, Int)] = []
            for (a, b) in iv {
                if let last = merged.last, a <= last.1 { merged[merged.count - 1].1 = max(last.1, b) }
                else { merged.append((a, b)) }
            }
            var uses = 0
            var lastEnd: Int? = nil
            for (a, b) in merged {
                if let le = lastEnd, a - le <= gapFrames { lastEnd = b; continue }
                uses += 1
                lastEnd = b
            }
            var w = previous[k] ?? MusicWork(key: k)
            w.clipNames = Array(Set(evs.map(\.clipName))).sorted()
            w.firstFrame = iv.first?.0 ?? 0
            w.totalFrames = merged.reduce(0) { $0 + ($1.1 - $1.0) }
            w.uses = uses
            w.tracks = Array(Set(evs.map(\.track))).sorted()
            if w.titel.isEmpty {
                if let lib = LibraryName.parse(k) {
                    // Production Music: Angaben aus dem Namensschema der Bibliothek (als Vorschlag markiert)
                    w.titel = lib.titel
                    w.quellen["titel"] = "Dateiname (\(lib.bibliothek))"
                    w.bibliothek = lib.bibliothek
                    w.trackID = lib.trackID
                    if !lib.album.isEmpty { w.beitrag = lib.album; w.quellen["beitrag"] = "Dateiname (\(lib.bibliothek))" }
                    if !lib.komponisten.isEmpty {
                        w.komponist = lib.komponisten
                        w.quellen["komponist"] = "Dateiname (\(lib.bibliothek), nur Nachnamen)"
                    }
                    w.verlag = lib.bibliothek
                    w.quellen["verlag"] = "Dateiname (Bibliothek – Verlag prüfen)"
                } else {
                    w.titel = titleSuggestion(k)
                    w.quellen["titel"] = "Dateiname"
                }
            }
            result.append(w)
        }
        return result.sorted { $0.firstFrame < $1.firstFrame }
    }

    static func mmss(_ seconds: Int) -> String { "\(seconds / 60):" + String(format: "%02d", seconds % 60) }
}
