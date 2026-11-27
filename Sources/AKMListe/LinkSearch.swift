import Foundation

/// Suchadressen für das manuelle Nachschlagen im Browser.
/// Es wird nur der Suchtext übertragen (Titel, Interpret bzw. Bibliothek/Track-ID) – keine Film- oder Projektdaten.
enum LinkSearch {
    static func query(_ w: MusicWork) -> String {
        if !w.bibliothek.isEmpty {
            return [w.beitrag, w.titel, w.trackID].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return [w.titel, w.interpret].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Websuche: Beitrag/Album + Titel (+ Interpret, falls nicht schon im Titel) und feste Suchbegriffe.
    static func webQuery(_ w: MusicWork) -> String {
        var parts = [w.beitrag, w.titel].filter { !$0.isEmpty }
        if !w.interpret.isEmpty && !w.titel.localizedCaseInsensitiveContains(w.interpret) { parts.append(w.interpret) }
        parts.append("Album Komponist Verlag Label")
        return parts.joined(separator: " ")
    }

    static func upmQuery(_ w: MusicWork) -> String {
        let t = w.titel.replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression)
        return (["site:universalproductionmusic.com", "\"\(t)\""] + (w.trackID.isEmpty ? [] : [w.trackID]))
            .joined(separator: " ")
    }

    private static func enc(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    static func google(_ q: String) -> URL { URL(string: "https://www.google.com/search?q=\(enc(q))")! }
    static func discogs(_ q: String) -> URL { URL(string: "https://www.discogs.com/search/?q=\(enc(q))&type=all")! }
    static func amazon(_ q: String) -> URL { URL(string: "https://www.amazon.de/s?k=\(enc(q))")! }
}
