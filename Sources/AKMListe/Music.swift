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

    func seconds(rate: FrameRate) -> Int { Int((Double(totalFrames) / rate.fps).rounded()) }
    var offen: [String] {
        var o: [String] = []
        if komponist.isEmpty { o.append("Komponist") }
        if verlag.isEmpty { o.append("Verlag") }
        if quellen["titel"] == "Dateiname" { o.append("Titel prüfen") }
        return o
    }
}

enum MusicAnalysis {
    private static let audioExt: Set<String> = ["wav", "aif", "aiff", "mp3", "m4a", "flac", "aac", "bwf", "mxf", "mov", "ogg"]
    private static let channelSuffix = try! NSRegularExpression(
        pattern: #"([ ._-](L|R|LEFT|RIGHT|A\d|CH\d|\d{1,2}CH)|\s*\((STEREO|MONO|L|R)\))$"#, options: [.caseInsensitive])

    static func key(for clip: String) -> String {
        var name = clip.trimmingCharacters(in: .whitespaces)
        let ext = (name as NSString).pathExtension.lowercased()
        if audioExt.contains(ext) { name = (name as NSString).deletingPathExtension }
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
            var lastEnd = Int.min
            for (a, b) in merged {
                if a - lastEnd > gapFrames { uses += 1 }
                lastEnd = b
            }
            var w = previous[k] ?? MusicWork(key: k)
            w.clipNames = Array(Set(evs.map(\.clipName))).sorted()
            w.firstFrame = iv.first?.0 ?? 0
            w.totalFrames = merged.reduce(0) { $0 + ($1.1 - $1.0) }
            w.uses = uses
            w.tracks = Array(Set(evs.map(\.track))).sorted()
            if w.titel.isEmpty {
                w.titel = titleSuggestion(k)
                w.quellen["titel"] = "Dateiname"
            }
            result.append(w)
        }
        return result.sorted { $0.firstFrame < $1.firstFrame }
    }

    static func mmss(_ seconds: Int) -> String { "\(seconds / 60):" + String(format: "%02d", seconds % 60) }
}
