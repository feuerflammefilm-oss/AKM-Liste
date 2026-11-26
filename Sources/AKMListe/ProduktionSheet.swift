import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Produktionsdaten – großzügig in zwei Spalten, nach Themen gruppiert.
/// Import/Export als .fuffprod: dieselbe Datei nutzen alle FuFF-Tools (Schnittliste, Dialogliste …).
struct ProduktionSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Produktionsdaten").font(.title2.weight(.semibold))
                Spacer()
                Button("Importieren …") { importFile() }
                    .help("Produktionsdaten aus einer .fuffprod-Datei laden (z. B. aus der Schnittliste)")
                Button("Exportieren …") { exportFile() }
                    .help("Als .fuffprod speichern, damit andere FuFF-Tools dieselben Angaben übernehmen")
            }
            ScrollView {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        group("Sendung") {
                            row("Sendetitel", $model.produktion.sendetitel)
                            row("Folge- / Untertitel", $model.produktion.untertitel)
                            row("Produktionsnummer", $model.produktion.produktionsnummer)
                            row("Folgenummer", $model.produktion.folgenummer)
                            row("Material-Nummer", $model.produktion.materialnummer)
                            GridRow {
                                Text("Produktionsart").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                Picker("", selection: $model.produktion.produktionsart) {
                                    Text("—").tag("")
                                    Text("Eigenproduktion").tag("Eigenproduktion")
                                    Text("Auftragsproduktion").tag("Auftragsproduktion")
                                    Text("Koproduktion").tag("Koproduktion")
                                }
                                .labelsHidden()
                            }
                        }
                        group("Ausstrahlung") {
                            GridRow {
                                Text("Art").foregroundStyle(.secondary)
                                Picker("", selection: $model.produktion.aufzeichnung) {
                                    Text("Aufzeichnung").tag(true)
                                    Text("Live").tag(false)
                                }
                                .pickerStyle(.segmented).labelsHidden()
                            }
                            row("1. Sendedatum", $model.produktion.sendedatum1, hint: "TT.MM.JJJJ")
                            row("Sendezeit von", $model.produktion.sendezeit1Von, hint: "hh:mm")
                            row("Sendezeit bis", $model.produktion.sendezeit1Bis, hint: "hh:mm")
                            row("2. Sendedatum", $model.produktion.sendedatum2, hint: "TT.MM.JJJJ")
                            row("Sendezeit von", $model.produktion.sendezeit2Von, hint: "hh:mm")
                            row("Sendezeit bis", $model.produktion.sendezeit2Bis, hint: "hh:mm")
                            row("Sendebereich", $model.produktion.sendebereich, hint: "z. B. ORF 2")
                        }
                    }
                    VStack(spacing: 18) {
                        group("Personen") {
                            row("Produzent", $model.produktion.produzent)
                            row("Regie", $model.produktion.regie)
                            row("Regieassistenz", $model.produktion.regieassistenz)
                            row("Autor / Gestalter", $model.produktion.autor)
                            row("Sprecher/in", $model.produktion.sprecher)
                            row("Redaktion", $model.produktion.redaktion)
                            row("S-Verantwortl. / Redakteur", $model.produktion.sendungsverantwortlich)
                            row("Für die Richtigkeit", $model.produktion.fuerRichtigkeit)
                        }
                        group("Firma & ORF") {
                            row("Firma / Dienststelle", $model.produktion.firma)
                            row("Telefon", $model.produktion.telefon)
                            row("Abteilung", $model.produktion.abteilung)
                            row("Verfasser-Code", $model.produktion.verfasserCode)
                            row("Nummer", $model.produktion.nummer)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text(message).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 820, idealWidth: 900, minHeight: 520, idealHeight: 640)
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        GroupBox(title) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) { content() }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: String, _ value: Binding<String>, hint: String = "") -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            TextField(hint, text: value).textFieldStyle(.roundedBorder).frame(minWidth: 200)
        }
    }

    private var fuffType: UTType { UTType(filenameExtension: Produktionsdaten.fileExtension) ?? .json }

    private func importFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [fuffType, .json]
        if p.runModal() == .OK, let u = p.url {
            do { model.produktion = try Produktionsdaten.load(from: u); message = "Geladen: \(u.lastPathComponent)" }
            catch { message = "Konnte nicht gelesen werden: \(error.localizedDescription)" }
        }
    }

    private func exportFile() {
        let p = NSSavePanel()
        p.allowedContentTypes = [fuffType]
        p.nameFieldStringValue = (model.produktion.sendetitel.isEmpty ? "Produktion" : model.produktion.sendetitel)
            + "." + Produktionsdaten.fileExtension
        if p.runModal() == .OK, let u = p.url {
            do { try model.produktion.save(to: u); message = "Gespeichert: \(u.lastPathComponent)" }
            catch { message = "Speichern fehlgeschlagen: \(error.localizedDescription)" }
        }
    }
}
