import Foundation

/// Erkennt Production-Music-Dateinamen und zerlegt sie nach dem Schema der Bibliothek.
/// Alles ist nur ein VORSCHLAG aus dem Dateinamen (in der App so markiert).
///
/// Universal Production Music (UPM), beobachtet an echten Clipnamen:
///   UPM <Album-Code> <Track-Nr.> <Titel> <Fassung> <Komponisten (Nachnamen)> <Track-ID>
///   z. B. „UPM ARX57 4 GOT THAT SWING INSTRUMENTAL BERGER 2055582“
struct LibraryName: Equatable {
    var bibliothek: String
    var album: String
    var titel: String
    var fassung: String
    var komponisten: String
    var trackID: String

    /// Wörter, die eine Fassung kennzeichnen (Titel endet davor, danach folgen die Komponisten)
    static let versionWords: Set<String> = [   // nur eindeutige Kennzeichnungen (Titelwörter wie „Long“ nicht)
        "INSTRUMENTAL", "UNDERSCORE", "STINGER", "STING", "ALT", "ALTERNATIVE", "MAIN", "FULL", "LOOP",
        "CUTDOWN", "BUMPER", "STEM", "STEMS", "NODRUMS", "VOCAL", "VOCALS", "10", "15", "20", "30", "45", "60", "90",
    ]

    static func parse(_ name: String) -> LibraryName? {
        let words = name.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count >= 5, words[0].uppercased() == "UPM",
              words[1].range(of: #"^[A-Za-z]{2,6}\d{1,4}[A-Za-z]?$"#, options: .regularExpression) != nil,
              Int(words[2]) != nil,
              let last = words.last, last.range(of: #"^\d{5,9}$"#, options: .regularExpression) != nil
        else { return nil }
        let middle = Array(words[3..<(words.count - 1)])
        guard !middle.isEmpty else { return nil }
        var titelWords = middle
        var fassung: [String] = []
        var komponisten: [String] = []
        if let vi = middle.firstIndex(where: { versionWords.contains($0.uppercased()) }), vi > 0 {
            titelWords = Array(middle[..<vi])
            var j = vi
            while j < middle.count, versionWords.contains(middle[j].uppercased()) { fassung.append(middle[j]); j += 1 }
            komponisten = Array(middle[j...])
        }
        let titel = cap(titelWords.joined(separator: " "))
        return LibraryName(
            bibliothek: "Universal Production Music",
            album: "UPM \(words[1].uppercased())",
            titel: fassung.isEmpty ? titel : "\(titel) (\(cap(fassung.joined(separator: " "))))",
            fassung: cap(fassung.joined(separator: " ")),
            komponisten: komponisten.map(cap).joined(separator: ", "),
            trackID: last)
    }

    /// „GOT THAT SWING“ → „Got That Swing“ (Namen wie O'HALLORAN → O'Halloran)
    static func cap(_ s: String) -> String {
        s.lowercased().split(separator: " ").map { w -> String in
            var r = ""
            var up = true
            for ch in w {
                r.append(up ? Character(String(ch).uppercased()) : ch)
                up = (ch == "'" || ch == "-")
            }
            return r
        }.joined(separator: " ")
    }
}
