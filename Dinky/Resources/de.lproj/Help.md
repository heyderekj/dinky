# Welcome

Dinky macht Dateien dinky. Legen Sie etwas hinein und holen Sie sich eine kleinere Version heraus – gleiches Aussehen, weniger Gewicht.

Es funktioniert mit **Bildern** (JPEG, PNG, WebP, AVIF, TIFF, BMP), **Videos** (MP4, MOV, M4V) und **PDFs**.

Alles geschieht auf Ihrem Mac. Es wird nichts hochgeladen.

---

## Quick start

1. Ziehen Sie eine Datei (oder einen Stapel davon) auf Dinkys Fenster.
2. Beobachten Sie, wie die Zählung sinkt.
3. Suchen Sie die kleineren Kopien neben den Originalen (Standard), in Ihrem Download-Ordner oder in einem Ordner Ihrer Wahl.

Das ist es. Die Standardwerte sind gut. Lesen Sie weiter, wenn Sie sie Ihrem Willen unterwerfen möchten.

---

## Ways to compress

Sie müssen die App nicht zuerst öffnen. Wählen Sie, was zu Ihrer Arbeitsweise passt.

- **Drag & Drop** auf das Dinky-Fenster oder das Dock-Symbol.
- **Dateien öffnen…** – „{{SK_OPEN_FILES}}“ zum Auswählen aus einem Blatt.
- **Zwischenablage komprimieren** – „{{SK_PASTE}}“ fügt eine unterstützte **Datei** ein, die im Finder kopiert wurde (Bilder, Videos, PDFs) oder **Rohbilddaten** (PNG/TIFF aus Screenshots oder Browsern).
- **Rechtsklick im Finder → Dienste → Mit Dinky komprimieren** – funktioniert bei Auswahlen jeder Größe.
- **Beobachten Sie einen Ordner** – Dinky komprimiert alles Neue, das darin landet. (Siehe *Ordner überwachen* unten.)
- **Schnellaktion** – Weisen Sie „Mit Dinky komprimieren“ in den Systemeinstellungen → Tastatur → Tastaturkürzel → Dienste eine Tastenkombination zu.

---

## Where files go

Stellen Sie dies einmal unter **Einstellungen → Ausgabe** ein.

- **Gleicher Ordner wie das Original** *(Standard)* – sorgt für Ordnung und Lokalität.
- **Downloads-Ordner** – gut, wenn Sie viele E-Mails oder Nachrichten verarbeiten.
- **Benutzerdefinierter Ordner…** – zeigen Sie Dinky an eine beliebige Stelle.

### Filenames

- **„-dinky“ anhängen** *(Standard)* – „photo.jpg“ wird zu „photo-dinky.jpg“. Originale sind sicher.
- **Original ersetzen** – überschreibt die Datei. Kombinieren Sie es mit *Originale in den Papierkorb verschieben* unter **Allgemein**, wenn Sie am Ende eine saubere Datei haben möchten.
- **Benutzerdefiniertes Suffix** – für Workflow-Tüftler. Verwenden Sie, was zu Ihrem Ablagesystem passt.

> **Profi-Tipp:** Voreinstellungen können den Speicherort und den Dateinamen pro Regel überschreiben. Verwenden Sie das für Dinge wie „Screenshots → „~/Desktop/web/“, Original ersetzen“.

---

## Sidebar & formats

In der Seitenleiste rechts im Hauptfenster sagen Sie Dinky, **was** er machen soll.

### Simple sidebar (default)

Drei Optionen im Klartext: **Bild**, **Video**, **PDF**. Wählen Sie eine pro Kategorie aus und lassen Sie sie fallen. Dinky findet einen sinnvollen Encoder, Qualität und Größe heraus.

### Full sidebar

Schalten Sie **Einstellungen → Allgemein → Einfache Seitenleiste verwenden** aus (oder schalten Sie einzelne Abschnitte ein), um alle Steuerelemente anzuzeigen:

- **Bilder** – Format, Inhaltshinweis (Foto/Illustration/Screenshot), maximale Breite, maximale Dateigröße.
- **Videos** – Codec-Familie (H.264 / HEVC / AV1), Qualitätsstufe, Strip-Audio.
- **PDFs** – Text und Links bleiben erhalten oder für die kleinstmögliche Datei auf Bilder reduziert.

---

## Smart quality

Wenn **Intelligente Qualität** aktiviert ist (Standard für neue Voreinstellungen), prüft Dinky jede Datei und wählt Einstellungen dafür aus:

- Bilder erhalten einen Encoder, der auf ihren Inhalt abgestimmt ist (beschäftigtes Foto vs. Grafik – Benutzeroberfläche, Illustration, Logo, Screenshot).
- Videos erhalten eine Stufe basierend auf Auflösung und Quellbitrate und werden dann nach Inhaltstyp angepasst. Bildschirmaufnahmen und Animationen/Motion-Grafiken werden um eine Stufe nach oben verschoben, sodass Text und Ränder lesbar bleiben. Kameraaufnahmen werden anhand der EXIF-Marke/des EXIF-Modells identifiziert, sodass sie nicht übermäßig geschützt sind. HDR-Quellen (Dolby Vision, HDR10, HLG) werden mit HEVC exportiert, um Farben zu erhalten und Details hervorzuheben; H.264 würde sie stillschweigend auf SDR reduzieren.
- PDFs erhalten eine Stufe basierend auf der Komplexität des Dokuments und darauf, ob sie textlastig oder bildlastig sind.

Deaktivieren Sie es in einer beliebigen Voreinstellung unter **Komprimierung**, wenn Sie eine feste Qualitätsstufe wünschen (Ausgewogen/Hoch für Videos, Niedrig/Mittel/Hoch für PDFs) – nützlich für Stapel, die vorhersehbare Ergebnisse erfordern.

---

## Presets

Voreinstellungen sind gespeicherte Kombinationen von Einstellungen. Erstellen Sie eine für jede wiederkehrende Aufgabe.

Beispiele, die gut funktionieren:

- **Web Hero-Bilder** – WebP, maximale Breite 1920, „-web“ anhängen.
- **Client-Deliverables** – WebP, maximale Breite 2560, Original ersetzen, unter „~/Deliverables/“ speichern.
- **Bildschirmaufnahmen** – H.264 symmetrisch, Strip-Audio.
- **Gescannte PDFs** – reduzieren, mittlere Qualität, Graustufen.

Erstellen Sie sie in **Einstellungen → Voreinstellungen**. Jeder kann:

- Auf alle Medien oder nur einen Typ (Bild / Video / PDF) anwenden.
- Verwenden Sie eine eigene Speicherort- und Dateinamensregel.
- Beobachten Sie einen eigenen Ordner *(siehe unten)*.
- Entfernen Sie Metadaten, bereinigen Sie Dateinamen und öffnen Sie anschließend den Ausgabeordner.

Wechseln Sie jederzeit in der Seitenleiste zur aktiven Voreinstellung.

---

## Watch folders

Legen Sie Dateien in einem Ordner ab und lassen Sie Dinky sie im Hintergrund verwalten.

- **Globale Überwachung** – *Einstellungen → Überwachung → Global*. Verwendet alles, worauf die Seitenleiste derzeit eingestellt ist. Gut für einen „Eingangs“- oder Screenshot-Ordner.
- **Überwachung pro Voreinstellung** – jede Voreinstellung kann auch ihren eigenen Ordner mit eigenen Regeln überwachen. Unabhängig von der Seitenleiste – ändern Sie die Seitenleiste nach Belieben, die Voreinstellung funktioniert weiterhin.

> **Profi-Tipp:** Kombinieren Sie „Bildschirmaufzeichnungsordner“ + eine Voreinstellung, die Audio entfernt und in H.264 Balanced neu kodiert. Klicken Sie auf „⌘⇧5“, Bildschirmaufnahme, Stopp – Dinky hat eine kleine Datei bereit, bevor Sie den Finder erreichen.

---

## Manual mode

Aktivieren Sie **Einstellungen → Allgemein → Manueller Modus**, wenn Sie die volle Kontrolle wünschen.

Eingefügte Dateien werden nicht automatisch komprimiert. Klicken Sie mit der rechten Maustaste auf eine beliebige Zeile, um sofort ein Format auszuwählen, verwenden Sie **Datei → Jetzt komprimieren** (`{{SK_COMPRESS_NOW}}`), wenn die Warteschlange bereit ist, oder ändern Sie zuerst die Einstellungen in der Seitenleiste. Nützlich, wenn ein Stapel sehr unterschiedliche Dateien enthält.

---

## Keyboard shortcuts

Sie finden dieselbe Liste unter **Einstellungen → Verknüpfungen**, sodass Sie sich nicht durch diese Seite wühlen müssen.

| Verknüpfung | Aktion |
| --- | --- |
| `{{SK_OPEN_FILES}}` | Dateien öffnen… |
| `{{SK_PASTE}}` | Zwischenablage komprimieren |
| `{{SK_COMPRESS_NOW}}` | Jetzt komprimieren (führt die Warteschlange aus – besonders nützlich im manuellen Modus) |
| `{{SK_CLEAR_ALL}}` | Alles löschen |
| `{{SK_TOGGLE_SIDEBAR}}` | Format-Seitenleiste umschalten |
| `{{SK_DELETE}}` | Ausgewählte Zeilen löschen |
| `{{SK_SETTINGS}}` | Einstellungen |
| `{{SK_HELP}}` | Dieses Hilfefenster |

Fügen Sie Ihre eigene für *Compress with Dinky* in **Systemeinstellungen → Tastatur → Tastaturkürzel → Dienste** hinzu.

---

## Shortcuts app

Dinky registriert eine Aktion **Bilder komprimieren** für die Shortcuts-App. Verwenden Sie es, um Finder-Dateien oder andere Aktionen mit einem ausgewählten Format über Dinky weiterzuleiten – dieselbe Engine wie die In-App-Komprimierung (berücksichtigt Einstellungen für intelligente Qualität, Größenänderung und Metadaten).

---

## Privacy & safety

- Alles läuft **lokal**. Keine Uploads, keine Telemetrie, kein Konto.
- **Absturzberichte** werden nur gesendet, wenn *Sie* dies wünschen – über die Eingabeaufforderung nach dem Absturz, das Menü „Fehler melden…“ oder das Fehlerdetailblatt. Wenn Sie in den Systemeinstellungen die Freigabe von macOS-Diagnosen aktiviert haben, übermittelt Apple in Ihrem Namen über MetricKit auch anonymisierte Absturzdaten an Dinky, ohne dass zusätzliche Daten Ihren Mac verlassen.
- Die Encoder („cwebp“, „avifenc“, „oxipng“ sowie die integrierten PDF- und AVFoundation-Videopipelines von Apple) werden in die App integriert und lesen Ihre Dateien direkt.
- Originale werden standardmäßig aufbewahrt. *Originale nach dem Komprimieren in den Papierkorb verschieben* ist in **Einstellungen → Allgemein** optional.
- *Überspringen, wenn die Einsparungen unten liegen* (standardmäßig deaktiviert) schützt bereits schlanke Dateien davor, umsonst neu codiert zu werden.
- *Metadaten entfernen* in jeder Voreinstellung entfernt EXIF, GPS, Kamerainformationen und Farbprofile. Es lohnt sich, Fotos im Internet zu veröffentlichen.

---

## Troubleshooting

**Eine Datei war größer als das Original.**
Dinky behält stattdessen das Original. In der Zeile wird *„Konnte nicht kleiner gemacht werden. Das Original bleibt beibehalten.“* angezeigt.

**Eine Datei wurde übersprungen.**
Entweder war es bereits sehr klein (unter Ihrem Schwellenwert *Überspringen, wenn Einsparungen darunter liegen*), oder der Encoder konnte es nicht lesen. Klicken Sie auf die Zeile, um Einzelheiten anzuzeigen.

**Ein Video dauert lange.**
Die Neukodierung von Videos ist CPU-lastig. Die Einstellung *Stapelgeschwindigkeit* unter **Einstellungen → Allgemein** steuert, wie viele Dateien gleichzeitig ausgeführt werden – setzen Sie sie auf **Schnell**, wenn Ihr Mac andere Dinge tut.

**Mein PDF hat die Textauswahl/Hyperlinks verloren.**
Sie haben *Flatten (am kleinsten)* verwendet. Schalten Sie die PDF-Ausgabe der Voreinstellung auf *Text und Links beibehalten* um und führen Sie sie erneut aus. Bei der Größe gewinnt Flatten immer; Bewahren gewinnt immer an Nützlichkeit.

**Rechtsklick „Mit Dinky komprimieren“ wird nicht angezeigt.**
Öffnen Sie Dinky nach der Installation einmal, damit macOS den Dienst registriert. Wenn es immer noch nicht angezeigt wird, aktivieren Sie es unter **Systemeinstellungen → Tastatur → Tastaturkürzel → Dienste → Dateien und Ordner**.

**Warum gibt Dinky kein JPEG aus?**
WebP und AVIF sind deutlich besser als JPEG – gleiche visuelle Qualität, kleinere Datei und werden überall dort unterstützt, wo es darauf ankommt. Wenn Ihre Plattform eine „.jpg“-Datei erfordert, versuchen Sie es zuerst mit WebP. Mittlerweile wird es fast überall akzeptiert. Wenn Sie auf eine Stelle stoßen, die dies wirklich ablehnt, nehmen Sie Kontakt mit uns auf und lassen Sie es uns wissen.

---

## Get in touch

- Website: [dinkyfiles.com](https://dinkyfiles.com)
- Code und Probleme: [github.com/heyderekj/dinky](https://github.com/heyderekj/dinky)
- E-Mail: [help@dinkyfiles.com](mailto:help@dinkyfiles.com)

Gebaut von Derek Castelli. Vorschläge, Bugs und „Könnte das auch gehen…“ sind willkommen.
