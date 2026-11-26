"""Prüft die von der App erzeugte ORF-AKM-Liste (läuft beim Bauen auf GitHub)."""
import sys
from openpyxl import load_workbook

def check(path, mode):
    wb = load_workbook(path)
    ws = wb["Musikaufstellung"]
    fails = []
    def eq(ref, want):
        got = ws[ref].value
        if got != want: fails.append(f"{ref}: erwartet {want!r}, ist {got!r}")
    eq("A1", "Musikaufstellung für ORF-Fernsehproduktionen")      # Vorlage intakt
    eq("A14", "Beitrag"); eq("AS14", "Min."); eq("AU14", "Sek.")
    eq("H3", "00/TEST/001"); eq("H4", "Testfilm (synthetisch)"); eq("H7", "Regie Test")
    eq("K11", "Bearbeiter Test"); eq("K12", "Testfirma"); eq("AH12", "0000/000000")
    eq("AR10", "ORF 2"); eq("AD3", "x")
    if mode == "klein":
        eq("G15", "Donauwalzer Probe"); eq("AS15", None); eq("AU15", 24)   # 17,96 s + 5,84 s = 23,8 s → 0:24
        eq("G16", "Spannung Loop"); eq("AU16", 7)
        eq("G17", None)
    else:
        eq("G15", "Testwerk 01"); eq("AU15", 15)      # 10 s + 5 s zusammengerechnet
        eq("G16", "Testwerk 02"); eq("AU16", 10)      # Stereo nicht doppelt
        eq("G69", "Testwerk 55"); eq("AU69", 10)      # Zeile 69 > 63: angehängt
        merged = {str(m) for m in ws.merged_cells.ranges}
        for r in ("G69:L69", "A69:F69", "AK69:AP69"):
            if r not in merged: fails.append(f"Zellverbund {r} fehlt in angehängter Zeile")
        if ws["G69"].border.left.style is None and ws["G63"].border.left.style is not None:
            fails.append("angehängte Zeile 69 hat keine Rahmen wie die Vorlage")
    pt = wb.defined_names.get("_xlnm.Print_Titles") if hasattr(wb.defined_names, "get") else None
    if ws.page_setup.orientation != "landscape": fails.append("nicht Querformat")
    print(f"{path}: {'OK' if not fails else 'FEHLER'}")
    for f in fails: print("  -", f)
    return not fails

ok = check(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "klein")
sys.exit(0 if ok else 1)
