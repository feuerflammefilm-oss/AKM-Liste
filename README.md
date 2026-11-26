# FuFF AKM-Liste

Mac-App, die aus der **EDL** eines fertig geschnittenen Films die **ORF-Musikaufstellung (AKM-Liste)** erstellt.
Teil der FuFF Tools (Converter, Transcriber, AKM-Liste, Schnittliste, Text- & Dialogliste).

## Funktionen

- **EDL hineinziehen** (Avid, Premiere, Resolve – CMX3600; auch mehrere EDLs, z. B. eine je Spur)
- **Musikspuren wählen** – Spuren mit Audiodateien (MP3, WAV, M4A …) sind vorausgewählt
- **Gesamtdauer je Werk**: Kommt ein Stück mehrmals vor, werden die Einsätze zusammengerechnet.
  Stereo-Doppelungen und Überlappungen zählen nicht doppelt.
- **Recherche** fehlender Angaben (Komponist, Textautor, Bearbeiter, Verlag/Label, Album) über MusicBrainz –
  fragt vorher nach, sendet nur Titel/Dateinamen, überschreibt nie eigene Eingaben
- **Produktionsdaten** (Titel, Produktionsnummer, Regie …) einmal eingeben und als `.fuffprod` mit den
  anderen FuFF-Tools teilen
- **Export** in die ORF-Vorlage (Excel), mit Fortschrittsanzeige; über 49 Werke werden Zeilen angehängt

Läuft auf **Apple Silicon und Intel ab macOS 13**. Eingaben werden automatisch gespeichert.

## Installieren

1. Unter **Releases → „latest“** `FuFF-AKM-Liste.zip` herunterladen.
2. Entpacken und **FuFF AKM-Liste.app** in **Programme** ziehen.
3. Erster Start: **Rechtsklick → Öffnen**, oder **Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“**.

## Bauen

Jeder Push auf `main` baut die App per GitHub Actions (`scripts/build_app.sh`), prüft sie mit synthetischen
Test-EDLs (`Tests/`) und veröffentlicht sie als Release „latest“.
