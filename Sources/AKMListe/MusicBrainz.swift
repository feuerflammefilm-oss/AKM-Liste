import Foundation

/// Recherche über die öffentliche MusicBrainz-API (kostenlos, kein Schlüssel, ~1 Anfrage/s).
/// Übertragen werden nur die angezeigten Suchbegriffe. Treffer sind Vorschläge, keine Rechtefreigabe.
struct ResearchCandidate: Identifiable, Hashable {
    let id = UUID()
    var titel: String
    var interpret: String
    var album: String
    var dauer: String
    var recordingID: String
    var releaseID: String
    var score: Int
}

struct ResearchLog: Identifiable, Hashable {
    let id = UUID()
    var zeit = Date()
    var url: String
    var anfrage: String
    var ergebnis: String
}

enum ResearchError: LocalizedError {
    case offline(String), timeout, http(Int)
    var errorDescription: String? {
        switch self {
        case .offline(let s): return "Keine Verbindung zu MusicBrainz (\(s))"
        case .timeout: return "Zeitüberschreitung bei MusicBrainz"
        case .http(let c): return "MusicBrainz antwortet mit Fehler \(c)"
        }
    }
}

actor MusicBrainz {
    static let shared = MusicBrainz()
    private let base = "https://musicbrainz.org/ws/2"
    private var last = Date.distantPast
    private let agent: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "FuFF-AKM-Liste/\(v) (Desktop-App fuer ORF-Musiklisten)"
    }()

    private func get(_ url: URL) async throws -> [String: Any] {
        for attempt in 0..<3 {
            let wait = 1.1 - Date().timeIntervalSince(last)
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            last = Date()
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.setValue(agent, forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 503 || code == 429 {
                    try await Task.sleep(nanoseconds: UInt64(2_000_000_000 * (attempt + 1)))
                    continue
                }
                if code == 404 { return [:] }
                guard code == 200 else { throw ResearchError.http(code) }
                return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            } catch let e as URLError where e.code == .timedOut {
                throw ResearchError.timeout
            } catch let e as URLError {
                throw ResearchError.offline(e.localizedDescription)
            }
        }
        throw ResearchError.http(503)
    }

    /// Suchteile aus dem Titel/Dateinamen – Jahreszahlen und Wiederholungen werden weggelassen.
    static func searchTerms(for w: MusicWork) -> [String] {
        let text = w.titel.isEmpty ? w.key : w.titel
        var parts: [String] = []
        for p in text.components(separatedBy: " - ") {
            let t = p.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.range(of: #"^(19|20)\d\d$"#, options: .regularExpression) != nil { continue }
            if !parts.contains(where: { $0.lowercased() == t.lowercased() }) { parts.append(t) }
        }
        if !w.interpret.isEmpty && !parts.contains(w.interpret) { parts.append(w.interpret) }
        return parts
    }

    private static func q(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    func search(_ w: MusicWork) async throws -> (url: String, candidates: [ResearchCandidate]) {
        let parts = Self.searchTerms(for: w)
        let query = parts.map { p in
            "(recording:\"\(Self.q(p))\" OR artist:\"\(Self.q(p))\" OR release:\"\(Self.q(p))\")"
        }.joined(separator: " AND ")
        var c = URLComponents(string: "\(base)/recording")!
        c.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "limit", value: "8"),
                        URLQueryItem(name: "fmt", value: "json")]
        let url = c.url!
        let d = try await get(url)
        let recs = d["recordings"] as? [[String: Any]] ?? []
        let cands: [ResearchCandidate] = recs.map { r in
            let artist = (r["artist-credit"] as? [[String: Any]] ?? [])
                .map { "\($0["name"] as? String ?? "")\($0["joinphrase"] as? String ?? "")" }.joined()
            let rel = (r["releases"] as? [[String: Any]])?.first
            let ms = r["length"] as? Int ?? 0
            return ResearchCandidate(titel: r["title"] as? String ?? "", interpret: artist,
                                     album: rel?["title"] as? String ?? "",
                                     dauer: ms > 0 ? "\(ms / 60000):" + String(format: "%02d", (ms / 1000) % 60) : "",
                                     recordingID: r["id"] as? String ?? "", releaseID: rel?["id"] as? String ?? "",
                                     score: r["score"] as? Int ?? 0)
        }
        return (url.absoluteString, cands)
    }

    /// Details zur gewählten Aufnahme: Werk (Komponist, Textautor, Bearbeiter, Verlag) und Label der Veröffentlichung.
    func details(_ cand: ResearchCandidate) async throws -> (fields: [String: String], log: [ResearchLog]) {
        var fields: [String: String] = [:]
        var logs: [ResearchLog] = []
        let recURL = URL(string: "\(base)/recording/\(cand.recordingID)?inc=work-rels&fmt=json")!
        let rec = try await get(recURL)
        let works = (rec["relations"] as? [[String: Any]] ?? [])
            .filter { ($0["type"] as? String) == "performance" }
            .compactMap { ($0["work"] as? [String: Any])?["id"] as? String }
        logs.append(ResearchLog(url: recURL.absoluteString, anfrage: "Aufnahme \(cand.recordingID)",
                                ergebnis: works.isEmpty ? "keine Werkverknüpfung" : "Werk gefunden"))
        if let wid = works.first {
            let wURL = URL(string: "\(base)/work/\(wid)?inc=artist-rels+label-rels&fmt=json")!
            let w = try await get(wURL)
            var roles: [String: [String]] = [:]
            let map = ["composer": "komponist", "writer": "komponist", "lyricist": "autor",
                       "arranger": "bearbeiter", "publishing": "verlag"]
            for r in w["relations"] as? [[String: Any]] ?? [] {
                guard let t = r["type"] as? String, let f = map[t] else { continue }
                let name = ((r["artist"] as? [String: Any]) ?? (r["label"] as? [String: Any]))?["name"] as? String ?? ""
                if !name.isEmpty && !(roles[f] ?? []).contains(name) { roles[f, default: []].append(name) }
            }
            for (k, v) in roles { fields[k] = v.joined(separator: ", ") }
            logs.append(ResearchLog(url: wURL.absoluteString, anfrage: "Werk \(wid)",
                                    ergebnis: roles.isEmpty ? "keine Personen eingetragen" : roles.keys.sorted().joined(separator: ", ")))
        }
        if !cand.releaseID.isEmpty && fields["verlag"] == nil {
            let rURL = URL(string: "\(base)/release/\(cand.releaseID)?inc=labels&fmt=json")!
            let rel = try await get(rURL)
            let labels = (rel["label-info"] as? [[String: Any]] ?? [])
                .compactMap { ($0["label"] as? [String: Any])?["name"] as? String }
            var seen: [String] = []
            for l in labels where !seen.contains(l) { seen.append(l) }
            if !seen.isEmpty { fields["verlag"] = seen.joined(separator: ", ") }
            logs.append(ResearchLog(url: rURL.absoluteString, anfrage: "Veröffentlichung \(cand.releaseID)",
                                    ergebnis: seen.isEmpty ? "kein Label" : "Label: \(seen.joined(separator: ", "))"))
        }
        return (fields, logs)
    }
}
