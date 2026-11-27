import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var dropTargeted = false
    @State private var confirmResearch = false

    var body: some View {
        Group {
            if model.edls.isEmpty { dropZone } else { main }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Self.urls(from: providers) { urls in
                if urls.contains(where: { $0.pathExtension.lowercased() == AKMProjekt.fileExtension }),
                   !Self.confirmDiscard(model) { return }
                model.open(urls)
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(6).allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { Self.openPanel(model) } label: { Label("Öffnen", systemImage: "doc.badge.plus") }
                    .help("EDL aus dem Schnitt oder gespeicherte AKM-Liste (.fuffakm) öffnen (⌘O)")
                Button { Self.save(model, asNew: false) } label: { Label("Sichern", systemImage: "square.and.arrow.down") }
                    .disabled(model.edls.isEmpty)
                    .help("AKM-Liste mit allen Eingaben sichern (⌘S) – später wieder öffnen und weiterarbeiten")
                Button { model.showProduktion = true } label: { Label("Produktionsdaten", systemImage: "person.text.rectangle") }
                    .help("Kopfdaten der Liste (Titel, Produktionsnummer, Regie …) – auch für andere FuFF-Tools")
                Button { confirmResearch = true } label: { Label("Recherche", systemImage: "magnifyingglass") }
                    .disabled(model.researchTargets.isEmpty || model.busy != nil)
                    .help("Fehlende Angaben (Komponist, Verlag …) online bei MusicBrainz suchen – fragt vorher nach")
                Button { exportPanel() } label: { Label("Exportieren", systemImage: "square.and.arrow.up") }
                    .disabled(model.exportWorks.isEmpty || model.busy != nil)
                    .keyboardShortcut("e", modifiers: .command)
                    .help("ORF-Musikaufstellung als Excel-Datei speichern (⌘E)")
            }
        }
        .navigationTitle(model.windowTitle)
        .sheet(isPresented: $model.showTrackSheet) { TrackSheet().environmentObject(model) }
        .sheet(isPresented: $model.showProduktion) { ProduktionSheet().environmentObject(model) }
        .sheet(item: Binding(get: { model.busy.map { BusyBox(state: $0) } }, set: { if $0 == nil { model.busy = nil } })) { _ in
            BusySheet().environmentObject(model)
        }
        .alert("Online recherchieren?", isPresented: $confirmResearch) {
            Button("Recherchieren") { model.researchAll() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Für \(model.researchTargets.count) Werke werden nur die Titel bzw. Dateinamen an musicbrainz.org gesendet – keine Film- oder Projektdaten. Treffer sind Vorschläge, keine Rechtefreigabe. Deine eigenen Eingaben werden nie überschrieben.")
        }
    }

    // MARK: Startansicht

    private var dropZone: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note.list").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("EDL hierher ziehen").font(.title2.weight(.semibold))
            Text("Die App liest die Musikspuren, rechnet jedes Stück zu einer Gesamtdauer zusammen\nund füllt die ORF-Musikaufstellung. Gespeicherte AKM-Listen (.fuffakm) lassen sich ebenso öffnen.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Öffnen …") { Self.openPanel(model) }.controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: Hauptansicht

    private var main: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                WorkTable().environmentObject(model).frame(minWidth: 380)
                DetailView().environmentObject(model).frame(minWidth: 300, idealWidth: 360)
            }
            Divider()
            statusBar
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.produktion.sendetitel.isEmpty ? "Produktion ohne Titel" : model.produktion.sendetitel)
                    .font(.headline)
                Text(model.produktion.produktionsnummer.isEmpty ? "Produktionsnummer fehlt"
                     : "Prod.-Nr. \(model.produktion.produktionsnummer)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Produktionsdaten …") { model.showProduktion = true }
            Spacer()
            Text("Musikspuren: \(model.musicTracks.isEmpty ? "keine" : model.musicTracks.sorted().joined(separator: ", "))")
                .lineLimit(1).truncationMode(.middle)
            Button("Ändern …") { model.showTrackSheet = true }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var statusBar: some View {
        HStack {
            Text("\(model.visibleWorks.count) Werke")
            if !model.deletedWorks.isEmpty {
                Menu("· \(model.deletedWorks.count) gelöscht") {
                    ForEach(model.deletedWorks) { w in
                        Button("„\(w.titel)“ wiederherstellen") { model.restore(w.key) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Gelöschte Werke wieder in die Liste holen")
            }
            if model.excludedCount > 0 {
                Text("· \(model.excludedCount) nicht in der Liste").foregroundStyle(.secondary)
            }
            if model.openCount > 0 {
                Text("· \(model.openCount) mit offenen Angaben").foregroundStyle(.orange)
            }
            Spacer()
            if !model.warnings.isEmpty {
                Text("\(model.warnings.count) Hinweise zur EDL").foregroundStyle(.secondary)
                    .help(model.warnings.prefix(20).joined(separator: "\n"))
            }
        }
        .font(.callout).padding(.horizontal, 14).padding(.vertical, 6)
    }

    // MARK: Dateien

    static var projectType: UTType { UTType(filenameExtension: AKMProjekt.fileExtension) ?? .json }

    static func openPanel(_ model: AppModel) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.allowedContentTypes = [UTType(filenameExtension: "edl") ?? .plainText, .plainText, projectType]
        p.message = "EDL(s) aus dem Schnitt oder eine gespeicherte AKM-Liste (.fuffakm) wählen"
        if p.runModal() == .OK {
            if p.urls.contains(where: { $0.pathExtension.lowercased() == AKMProjekt.fileExtension }) {
                guard confirmDiscard(model) else { return }
            }
            model.open(p.urls)
        }
    }

    /// true = weitermachen (gesichert, verworfen oder nichts zu sichern)
    static func confirmDiscard(_ model: AppModel) -> Bool {
        guard model.dirty, !model.edls.isEmpty else { return true }
        let a = NSAlert()
        a.messageText = "Änderungen an „\(model.windowTitle.replacingOccurrences(of: " – bearbeitet", with: ""))“ sichern?"
        a.informativeText = "Sonst gehen Eingaben verloren, die noch nicht gesichert sind."
        a.addButton(withTitle: "Sichern")
        a.addButton(withTitle: "Nicht sichern")
        a.addButton(withTitle: "Abbrechen")
        switch a.runModal() {
        case .alertFirstButtonReturn: return save(model, asNew: false)
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    static func newList(_ model: AppModel) {
        guard confirmDiscard(model) else { return }
        model.closeAll()
    }

    @discardableResult
    static func save(_ model: AppModel, asNew: Bool) -> Bool {
        guard !model.edls.isEmpty else { return false }
        var target = asNew ? nil : model.projectURL
        if target == nil {
            let p = NSSavePanel()
            p.allowedContentTypes = [projectType]
            let t = model.produktion.sendetitel.isEmpty ? "AKM-Liste" : model.produktion.sendetitel
            p.nameFieldStringValue = "\(t).\(AKMProjekt.fileExtension)"
            p.message = "AKM-Liste sichern – enthält EDL, Eingaben und Produktionsdaten"
            guard p.runModal() == .OK, let u = p.url else { return false }
            target = u
        }
        do {
            try model.saveProject(to: target!)
            return true
        } catch {
            let a = NSAlert(error: error)
            a.runModal()
            return false
        }
    }

    private func exportPanel() {
        let p = NSSavePanel()
        p.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        let t = model.produktion.sendetitel.isEmpty ? "Musikaufstellung" : model.produktion.sendetitel
        p.nameFieldStringValue = "\(t) – ORF AKM-Liste.xlsx"
        if p.runModal() == .OK, let u = p.url { model.export(to: u) }
    }

    static func urls(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        var result: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    if let url { result.append(url) }
                    group.leave()      // erst nach dem Einsammeln – sonst fehlen Dateien
                }
            }
        }
        group.notify(queue: .main) { completion(result) }
    }
}

private struct BusyBox: Identifiable { let state: BusyState; var id: String { state.title } }

// MARK: - Werkliste

struct WorkTable: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let list = model.visibleWorks
        Table(list, selection: $model.selection) {
            TableColumn("Nr.") { w in Text("\((list.firstIndex(of: w) ?? 0) + 1)").monospacedDigit() }
                .width(min: 30, ideal: 36, max: 44)
            TableColumn("Titel") { w in
                Text(w.titel).lineLimit(1).strikethrough(w.ausschliessen).foregroundStyle(w.ausschliessen ? .secondary : .primary)
            }
                .width(min: 160, ideal: 260)
            TableColumn("Gesamt") { w in Text(MusicAnalysis.mmss(w.seconds(rate: model.rate))).monospacedDigit() }
                .width(min: 50, ideal: 60, max: 70)
            TableColumn("Einsätze") { w in Text("\(w.uses)").monospacedDigit() }
                .width(min: 50, ideal: 60, max: 70)
            TableColumn("Komponist") { w in Text(w.komponist).lineLimit(1) }
                .width(min: 100, ideal: 150)
            TableColumn("Offen") { w in
                if w.ausschliessen {
                    Text("nicht in der Liste").foregroundStyle(.secondary)
                } else {
                    Text(w.offen.joined(separator: ", ")).foregroundStyle(.orange).lineLimit(1)
                }
            }
            .width(min: 80, ideal: 140)
        }
        .contextMenu(forSelectionType: MusicWork.ID.self) { ids in
            Button("Aus der Liste löschen") { ids.forEach { model.delete($0) } }
                .disabled(ids.isEmpty)
        }
        .onDeleteCommand { if let k = model.selection { model.delete(k) } }
    }
}

// MARK: - Details zum gewählten Werk

struct DetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let key = model.selection, let w = model.binding(for: key) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(w.wrappedValue.titel).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Text("Gesamtdauer \(MusicAnalysis.mmss(w.wrappedValue.seconds(rate: model.rate))) aus \(w.wrappedValue.uses) Einsatz/Einsätzen · Spuren \(w.wrappedValue.tracks.joined(separator: ", "))")
                        .font(.callout).foregroundStyle(.secondary)
                    Toggle("Nicht in die AKM-Liste (z. B. Geräusch, Originalton-Gesang)", isOn: w.ausschliessen)
                        .help("Das Werk bleibt hier sichtbar, wird aber nicht exportiert.")
                    Button(role: .destructive) { model.delete(key) } label: {
                        Label("Werk aus der Liste löschen", systemImage: "trash")
                    }
                    .help("Entfernt das Werk aus Liste und Export (⌫). Wiederherstellen über „gelöscht“ unten in der Statuszeile.")
                    if !w.wrappedValue.bibliothek.isEmpty {
                        Label("Bibliotheksmusik: \(w.wrappedValue.bibliothek)\(w.wrappedValue.trackID.isEmpty ? "" : " · Track-ID \(w.wrappedValue.trackID)") – Angaben aus dem Dateinamen, Komponisten nur mit Nachnamen.",
                              systemImage: "building.columns")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    GroupBox("Angaben für die AKM-Liste") {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                            field("Beitrag / Album", w.beitrag, w.wrappedValue.quellen["beitrag"])
                            field("Titel", w.titel, w.wrappedValue.quellen["titel"])
                            field("Interpret", w.interpret, w.wrappedValue.quellen["interpret"])
                            field("Komponist", w.komponist, w.wrappedValue.quellen["komponist"])
                            field("Bearbeiter", w.bearbeiter, w.wrappedValue.quellen["bearbeiter"])
                            field("Autor (Text)", w.autor, w.wrappedValue.quellen["autor"])
                            field("Verlag / Label", w.verlag, w.wrappedValue.quellen["verlag"])
                            GridRow {
                                Text("")
                                HStack {
                                    Toggle("Musikvideo", isOn: w.musikvideo)
                                    Toggle("Live", isOn: w.live)
                                }
                            }
                        }
                        .padding(6)
                    }
                    if w.wrappedValue.bibliothek.isEmpty { researchBox(key: key) }
                    linkBox(w.wrappedValue)
                    GroupBox("Clips in der EDL") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(w.wrappedValue.clipNames, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                    }
                }
                .padding(14)
            }
        } else {
            VStack {
                Text("Werk in der Liste auswählen").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func field(_ label: String, _ value: Binding<String>, _ source: String?) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            VStack(alignment: .leading, spacing: 1) {
                TextField(label, text: value).textFieldStyle(.roundedBorder)
                if let s = source, !value.wrappedValue.isEmpty {
                    Text(s == "Dateiname" ? "aus dem Dateinamen – bitte prüfen" : "Quelle: \(s)")
                        .font(.caption2).foregroundStyle(s == "Dateiname" ? .orange : .secondary)
                }
            }
        }
    }

    /// Manuell nachschlagen: öffnet den Browser (kein automatisches Auslesen fremder Seiten).
    /// Gesendet wird nur der Suchtext, der unten angezeigt wird.
    private func linkBox(_ w: MusicWork) -> some View {
        let q = LinkSearch.query(w)
        return GroupBox("Im Browser nachschlagen") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button("Websuche") { open(LinkSearch.google(q)) }
                        .help("Google-Suche nach Titel und Interpret")
                    Button("KI-Suche") { open(LinkSearch.aiMode(LinkSearch.aiQuery(w))) }
                        .help("Google KI-Modus: fragt nach Komponist und Verlag – Antwort ist ein Hinweis, kein Beleg")
                    Button("Discogs") { open(LinkSearch.discogs(q)) }
                    Button("Amazon") { open(LinkSearch.amazon(q)) }
                        .help("Amazon.de – in den Produktdetails stehen oft Label und Komponist")
                }
                if !w.bibliothek.isEmpty {
                    HStack {
                        Button("UPM-Seite finden") { open(LinkSearch.google(LinkSearch.upmQuery(w))) }
                            .help("Google-Suche nur auf universalproductionmusic.com (Titel + Track-ID)")
                        Button("UPM-Website") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(w.trackID.isEmpty ? w.titel : w.trackID, forType: .string)
                            open(URL(string: "https://www.universalproductionmusic.com/")!)
                        }
                        .help("Öffnet die UPM-Website und kopiert die Track-ID – dort ins Suchfeld einfügen (⌘V)")
                    }
                }
                Text("Suchtext: „\(q)“ – die Seiten öffnen sich im Browser, Ergebnisse bitte selbst prüfen und eintragen. KI-Antworten können falsch sein (z. B. Notenvertrieb statt Musikverlag).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }
    }

    private func open(_ url: URL) { NSWorkspace.shared.open(url) }

    @ViewBuilder
    private func researchBox(key: String) -> some View {
        GroupBox("Recherche") {
            VStack(alignment: .leading, spacing: 8) {
                if let cands = model.candidates[key], !cands.isEmpty {
                    Text("\(cands.count) mögliche Treffer – passende Aufnahme wählen:").font(.callout)
                    ForEach(cands) { c in
                        Button {
                            Task { await model.choose(c, for: key) }
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(c.titel) – \(c.interpret)").fontWeight(.medium)
                                Text([c.album, c.dauer].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                HStack(spacing: 8) {
                    Button(model.candidates[key]?.isEmpty == false ? "Erneut suchen" : "Dieses Werk bei MusicBrainz suchen") {
                        model.researchOne(key)
                    }
                    .disabled(model.searching.contains(key))
                    if model.searching.contains(key) {
                        ProgressView().controlSize(.small)
                    }
                }
                Text("Sendet nur: \(MusicBrainz.searchTerms(for: model.works.first { $0.key == key } ?? MusicWork(key: key)).joined(separator: " / "))")
                    .font(.caption).foregroundStyle(.secondary)
                if let msg = model.searchStatus[key] {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(msg.hasPrefix("Fehler") ? Color.red : (msg.hasPrefix("Kein Treffer") ? Color.orange : Color.primary))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if !model.researchLog.isEmpty {
                    DisclosureGroup("Abfrage-Protokoll (\(model.researchLog.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(model.researchLog.suffix(12).reversed()) { l in
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("\(l.zeit.formatted(date: .omitted, time: .standard)) · \(l.anfrage) → \(l.ergebnis)")
                                        .font(.caption)
                                    if !l.url.isEmpty {
                                        Text(l.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }
    }
}

// MARK: - Musikspuren wählen

struct TrackSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Auf welchen Spuren liegt Musik?").font(.title3.weight(.semibold))
            Text("Vorgeschlagen sind Spuren, deren Clips Audiodateien sind (MP3, WAV, M4A …).")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.audioTracks, id: \.self) { t in
                        Toggle(isOn: Binding(
                            get: { model.musicTracks.contains(t) },
                            set: { on in if on { model.musicTracks.insert(t) } else { model.musicTracks.remove(t) } })) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t).fontWeight(.medium)
                                Text((model.trackExamples[t] ?? []).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160, maxHeight: 360)
            HStack {
                Picker("Bildrate der Sequenz", selection: $model.rate) {
                    ForEach(FrameRate.all) { Text("\($0.label) fps").tag($0) }
                }
                .frame(width: 260)
                .help("EDLs enthalten keine Bildrate. Sie bestimmt, wie Frames in Sekunden umgerechnet werden.")
                Spacer()
                Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

// MARK: - Fortschritt

struct BusySheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let b = model.busy {
                Text(b.title).font(.headline)
                ProgressView(value: b.fraction)
                Text(b.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                if let e = b.error {
                    Text(e).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    if let u = b.finishedURL {
                        Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([u]); model.busy = nil }
                        Button("Öffnen") { NSWorkspace.shared.open(u); model.busy = nil }
                            .keyboardShortcut(.defaultAction)
                    } else if b.error != nil {
                        Button("Schließen") { model.busy = nil }.keyboardShortcut(.defaultAction)
                    } else {
                        Button("Abbrechen") { model.cancelBusy() }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}
