import Foundation

// MARK: - Bildrate & Timecode

struct FrameRate: Hashable, Identifiable {
    let num: Int
    let den: Int
    let label: String
    var id: String { label }
    var fps: Double { Double(num) / Double(den) }
    var nominal: Int { Int(fps.rounded()) }
    var dropFrameAllowed: Bool { den == 1001 && (nominal == 30 || nominal == 60) }

    static let all: [FrameRate] = [
        FrameRate(num: 24000, den: 1001, label: "23,976"),
        FrameRate(num: 24, den: 1, label: "24"),
        FrameRate(num: 25, den: 1, label: "25"),
        FrameRate(num: 30000, den: 1001, label: "29,97"),
        FrameRate(num: 30, den: 1, label: "30"),
        FrameRate(num: 50, den: 1, label: "50"),
        FrameRate(num: 60000, den: 1001, label: "59,94"),
        FrameRate(num: 60, den: 1, label: "60"),
    ]
    static let standard = all[2]
    static func byLabel(_ s: String) -> FrameRate? {
        all.first { $0.label == s || $0.label.replacingOccurrences(of: ",", with: ".") == s }
    }
}

enum Timecode {
    /// "HH:MM:SS:FF" (";" = Drop-Frame) -> Frames. nil bei ungültigem Wert.
    static func frames(_ tc: String, rate: FrameRate, drop: Bool) -> Int? {
        let parts = tc.split(whereSeparator: { ":;.,".contains($0) }).map(String.init)
        guard parts.count == 4, let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]),
              let f = Int(parts[3]) else { return nil }
        let fps = rate.nominal
        guard m < 60, s < 60, f < fps else { return nil }
        let isDrop = drop || tc.contains(";") || tc.contains(",")
        if isDrop && rate.dropFrameAllowed {
            let d = rate.nominal == 30 ? 2 : 4
            let totalMin = 60 * h + m
            return (h * 3600 + m * 60 + s) * fps + f - d * (totalMin - totalMin / 10)
        }
        return (h * 3600 + m * 60 + s) * fps + f
    }
}

// MARK: - EDL (CMX3600)

struct EDLEvent {
    var number: String
    var track: String          // z. B. "A5" bzw. "Datei · A1" bei mehreren EDLs
    var recordIn: Int
    var recordOut: Int
    var sourceIn: Int
    var sourceOut: Int
    var reel: String
    var clipName: String
    var transition: String
    var duration: Int { recordOut - recordIn }
}

struct EDLFile {
    var url: URL
    var title: String = ""
    var events: [EDLEvent] = []
    var warnings: [String] = []
}

enum EDLParser {
    private static let tc = #"(\d{1,2}:\d{2}[:;.]\d{2}[:;.,]\d{2})"#
    private static let eventRE = try! NSRegularExpression(
        pattern: #"^(\d{1,6})\s+(\S+)\s+(\S+)\s+(C|D|W\d{1,3}|K|KB|KO)\s+(?:(\d{1,4})\s+)?"#
            + tc + #"\s+"# + tc + #"\s+"# + tc + #"\s+"# + tc + #"\s*$"#)
    private static let audRE = try! NSRegularExpression(pattern: #"^AUD\s+(\d+)(?:\s+(\d+))?\s*$"#)

    static func channels(_ token: String) -> [String]? {
        let t = token.uppercased()
        switch t {
        case "V": return ["V"]
        case "A", "A1": return ["A1"]
        case "A2": return ["A2"]
        case "AA": return ["A1", "A2"]
        case "B", "A/V", "V/A": return ["V", "A1"]
        case "AA/V", "V/AA": return ["V", "A1", "A2"]
        case "NONE": return []
        default:
            if t.range(of: #"^A\d{1,2}$"#, options: .regularExpression) != nil { return [t] }
            return nil
        }
    }

    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for enc: String.Encoding in [.utf8, .windowsCP1252, .macOSRoman, .isoLatin1] {
            if let s = String(data: data, encoding: enc) { return s }
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func parse(_ url: URL, rate: FrameRate, trackPrefix: String = "") throws -> EDLFile {
        var file = EDLFile(url: url)
        let text = try readText(url)
        var drop = false
        var current: [EDLEvent] = []      // Ereignisse der zuletzt gelesenen Zeile
        var previous: [EDLEvent] = []     // vorletzte Zeile mit gleicher Nummer (Blenden)
        var currentNumber = ""

        func flush(_ evs: [EDLEvent]) { file.events.append(contentsOf: evs.filter { $0.duration > 0 }) }

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        for (idx, raw) in lines.enumerated() {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            let up = s.uppercased()
            if up.hasPrefix("TITLE:") { file.title = String(s.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
            if up.hasPrefix("FCM:") { drop = up.contains("DROP") && !up.contains("NON"); continue }
            let ns = s as NSString
            if let m = eventRE.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
                func g(_ i: Int) -> String {
                    let r = m.range(at: i); return r.location == NSNotFound ? "" : ns.substring(with: r)
                }
                let number = g(1), reel = g(2), chan = g(3), trans = g(4)
                let tcs = (6...9).map { g($0) }
                let fr = tcs.map { Timecode.frames($0, rate: rate, drop: drop) }
                guard fr.allSatisfy({ $0 != nil }) else {
                    file.warnings.append("Zeile \(idx + 1): Ereignis \(number) nicht übernommen (ungültiger Timecode – Bildrate prüfen)")
                    continue
                }
                let v = fr.map { $0! }
                guard v[3] >= v[2] else {
                    file.warnings.append("Zeile \(idx + 1): Ereignis \(number) nicht übernommen (Record-Out vor Record-In)")
                    continue
                }
                if number == currentNumber {
                    previous = current            // Blende: Ausgangsclip bleibt offen, bis sein Name gelesen ist
                } else {
                    flush(previous + current)
                    previous = []
                }
                current = []
                currentNumber = number
                guard let chans = channels(chan) else {
                    file.warnings.append("Zeile \(idx + 1): unbekannter Kanal „\(chan)“ – übersprungen")
                    continue
                }
                for c in chans {
                    current.append(EDLEvent(number: number, track: trackPrefix + c, recordIn: v[2], recordOut: v[3],
                                            sourceIn: v[0], sourceOut: v[1], reel: reel, clipName: "",
                                            transition: trans))
                }
                continue
            }
            if let m = audRE.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), let base = current.first {
                for i in 1...2 {
                    let r = m.range(at: i)
                    if r.location != NSNotFound, let n = Int(ns.substring(with: r)) {
                        var e = base
                        e.track = trackPrefix + "A\(n)"
                        current.append(e)
                    }
                }
                continue
            }
            if s.hasPrefix("*") || up.hasPrefix("FROM CLIP NAME:") || up.hasPrefix("TO CLIP NAME:") {
                let body = s.drop(while: { $0 == "*" }).trimmingCharacters(in: .whitespaces)
                let bup = body.uppercased()
                let value = body.split(separator: ":", maxSplits: 1).dropFirst().first
                    .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                if bup.hasPrefix("FROM CLIP NAME:") {
                    if previous.isEmpty {
                        for i in current.indices { current[i].clipName = value }
                    } else {
                        for i in previous.indices { previous[i].clipName = value }
                    }
                } else if bup.hasPrefix("TO CLIP NAME:") {
                    // nur bei Übergängen (Blende/Wipe) ist TO der eingehende Clip; Avid schreibt es auch bei Schnitten
                    for i in current.indices where current[i].transition != "C" { current[i].clipName = value }
                }
                continue
            }
            if up.hasPrefix("M2 ") || up.hasPrefix("|C:") || up.hasPrefix("SPLIT:") || up.hasPrefix(">>>") { continue }
            if up.hasPrefix("EFFECTS NAME IS") { continue }
            file.warnings.append("Zeile \(idx + 1): nicht verstanden: \(s.prefix(60))")
        }
        flush(previous + current)
        if file.events.isEmpty { file.warnings.append("Keine Ereignisse gefunden – ist das eine CMX3600-EDL?") }
        return file
    }

    /// Größtes Frame-Feld in den Timecodes – hilft, eine falsche Bildrate zu erkennen.
    static func suggestedRate(_ url: URL) -> FrameRate {
        guard let text = try? readText(url) else { return .standard }
        var maxFrame = 0
        let re = try! NSRegularExpression(pattern: #"\d{2}[:;.]\d{2}[:;.]\d{2}[:;.,](\d{2})"#)
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            maxFrame = max(maxFrame, Int(ns.substring(with: m.range(at: 1))) ?? 0)
        }
        if maxFrame >= 50 { return FrameRate.all[5] }
        if maxFrame >= 25 { return FrameRate.all[4] }
        return .standard
    }
}
