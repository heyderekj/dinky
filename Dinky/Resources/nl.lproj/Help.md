# Welcome

Dinky maakt bestanden dinky. Laat er iets in vallen, haal er een kleinere versie uit: hetzelfde uiterlijk, minder gewicht.

Het werkt op **afbeeldingen** (JPEG, PNG, WebP, AVIF, TIFF, BMP), **video's** (MP4, MOV, M4V) en **PDF's**.

Alles gebeurt op je Mac. Er wordt niets geüpload.

---

## Quick start

1. Sleep een bestand (of een stapel daarvan) naar Dinky's venster.
2. Kijk hoe de telling afgaat.
3. Zoek de kleinere exemplaren naast de originelen (standaard), in uw map Downloads of in een map naar keuze.

Dat is het. De standaardinstellingen zijn goed. Lees verder als u ze naar uw hand wilt zetten.

---

## Ways to compress

Je hoeft de app niet eerst te openen. Kies wat bij uw manier van werken past.

- **Drag & drop** naar het Dinky-venster of het Dock-pictogram.
- **Bestanden openen…** — `{{SK_OPEN_FILES}}` om uit een blad te kiezen.
- **Klembordcompressie** — `{{SK_PASTE}}` plakt een ondersteund **bestand** gekopieerd in Finder (afbeeldingen, video's, PDF's) of **onbewerkte afbeelding**-gegevens (PNG/TIFF van schermafbeeldingen of browsers).
- **Klik met de rechtermuisknop in Finder → Services → Comprimeren met Dinky** — werkt op selecties van elk formaat.
- **Bekijk een map** — Dinky comprimeert alles wat erin terechtkomt. (Zie *Bekijkmappen* hieronder.)
- **Snelle actie** — wijs een sneltoets toe aan "Comprimeren met Dinky" in Systeeminstellingen → Toetsenbord → Sneltoetsen → Services.

---

## Where files go

Stel dit eenmalig in **Instellingen → Uitvoer**.

- **Dezelfde map als origineel** *(standaard)* — houdt alles netjes en lokaal.
- **Downloadmap** — goed als u veel e-mail of berichten verwerkt.
- **Aangepaste map...** — richt Dinky waar dan ook.

### Filenames

- **Voeg "-dinky" toe** *(standaard)* — `photo.jpg` wordt `photo-dinky.jpg`. Originelen zijn veilig.
- **Vervang origineel** — overschrijft het bestand. Combineer met *Verplaats originelen naar prullenbak* in **Algemeen** als je aan het eind één schoon bestand wilt.
- **Aangepast achtervoegsel** — voor de workflow-knutselaars. Gebruik wat bij uw archiefsysteem past.

> **Pro tip:** Voorinstellingen kunnen per regel de opslaglocatie en bestandsnaam overschrijven. Gebruik dat voor zaken als "screenshots → `~/Desktop/web/`, vervang origineel".

---

## Sidebar & formats

In de zijbalk aan de rechterkant van het hoofdvenster vertel je Dinky **wat** ze moet maken.

### Simple sidebar (default)

Drie keuzes in duidelijke taal: **Afbeelding**, **Video**, **PDF**. Kies er één per categorie en laat deze vallen. Dinky bedenkt een verstandige encoder, kwaliteit en grootte.

### Full sidebar

Schakel **Instellingen → Algemeen → Eenvoudige zijbalk gebruiken** uit (of schakel afzonderlijke secties in) om elk besturingselement zichtbaar te maken:

- **Afbeeldingen** — formaat, inhoudstip (foto/illustratie/screenshot), maximale breedte, maximale bestandsgrootte.
- **Video's** — codecfamilie (H.264 / HEVC / AV1), kwaliteitslaag, stripaudio.
- **PDF's** — behoud tekst en links, of maak afbeeldingen plat voor een zo klein mogelijk bestand.

---

## Smart quality

Wanneer **Slimme kwaliteit** is ingeschakeld (standaard voor nieuwe voorinstellingen), inspecteert Dinky elk bestand en kiest er instellingen voor:

- Afbeeldingen krijgen een encoder die is afgestemd op hun inhoud (drukke foto versus afbeelding - gebruikersinterface, illustratie, logo, screenshot).
- Video's krijgen een niveau op basis van resolutie en bronbitrate, en worden vervolgens aangepast op basis van het inhoudstype. Schermopnamen en animaties/bewegende afbeeldingen worden een niveau hoger geplaatst, zodat tekst en randen leesbaar blijven. Camerabeelden zijn geïdentificeerd op basis van het EXIF-merk/-model, zodat deze niet overbeveiligd zijn. HDR-bronnen (Dolby Vision, HDR10, HLG) worden geëxporteerd met HEVC om de kleuren te behouden en details te benadrukken; H.264 zou ze stilletjes afvlakken tot SDR.
- PDF's krijgen een niveau op basis van de complexiteit van het document en of ze eerst tekst of veel afbeeldingen bevatten.

Schakel het uit in een willekeurige voorinstelling onder **Compressie** als u een vast kwaliteitsniveau wilt (Balanced / Hoog voor video, Laag / Medium / Hoog voor PDF's) - handig voor batches die voorspelbare resultaten nodig hebben.

---

## Presets

Voorinstellingen zijn opgeslagen combinaties van instellingen. Bouw er één voor elke herhalende taak.

Voorbeelden die goed werken:

- **Webheld-afbeeldingen** — WebP, maximale breedte 1920, voeg `-web` toe.
- **Client deliverables** — WebP, maximale breedte 2560, vervang origineel, sla op in `~/Deliverables/`.
- **Schermopnamen** — H.264 Gebalanceerde, stripaudio.
- **Gescande PDF's** — plat, gemiddelde kwaliteit, grijstinten.

Maak ze in **Instellingen → Voorinstellingen**. Elk kan:

- Toepassen op alle media of slechts één type (Afbeelding / Video / PDF).
- Gebruik zijn eigen opslaglocatie en bestandsnaamregel.
- Bekijk de eigen map *(zie hieronder)*.
- Verwijder metagegevens, zuiver bestandsnamen en open de uitvoermap als u klaar bent.

Schakel op elk gewenst moment de actieve voorinstelling vanuit de zijbalk.

---

## Watch folders

Zet bestanden in een map en laat Dinky ze op de achtergrond afhandelen.

- **Globaal horloge** — *Instellingen → Horloge → Globaal*. Gebruikt waar de zijbalk momenteel op is ingesteld. Goed voor een map "inkomend" of screenshot.
- **Bewaking per preset** — elke preset kan ook zijn eigen map met zijn eigen regels bekijken. Onafhankelijk van de zijbalk: verander de zijbalk zoveel je wilt, de preset doet nog steeds zijn ding.

> **Pro tip:** Combineer de map 'Schermopnamen' + een voorinstelling die audio verwijdert en opnieuw codeert naar H.264 Balanced. Druk op `⌘⇧5`, schermopname, druk op stop - Dinky heeft een klein bestand klaar voordat je de Finder bereikt.

---

## Manual mode

Schakel **Instellingen → Algemeen → Handmatige modus** in als u volledige controle wilt.

Bestanden die binnenkomen, worden niet automatisch gecomprimeerd. Klik met de rechtermuisknop op een rij om ter plekke een indeling te kiezen, gebruik **Bestand → Nu comprimeren** (`{{SK_COMPRESS_NOW}}`) wanneer de wachtrij gereed is, of wijzig eerst de instellingen in de zijbalk. Handig als één batch zeer verschillende bestanden bevat.

---

## Keyboard shortcuts

U vindt dezelfde lijst in **Instellingen → Snelkoppelingen**, zodat u deze pagina niet hoeft te doorzoeken.

| Sneltoets | Actie |
| --- | --- |
| `{{SK_OPEN_FILES}}` | Bestanden openen… |
| `{{SK_PASTE}}` | Klembord comprimeren |
| `{{SK_COMPRESS_NOW}}` | Nu comprimeren (voert de wachtrij uit - vooral handig in de handmatige modus) |
| `{{SK_CLEAR_ALL}}` | Alles wissen |
| `{{SK_TOGGLE_SIDEBAR}}` | Zijbalk opmaken |
| `{{SK_DELETE}}` | Geselecteerde rijen verwijderen |
| `{{SK_SETTINGS}}` | Instellingen |
| `{{SK_HELP}}` | Dit Help-venster |

Voeg je eigen toe voor *Comprimeren met Dinky* in **Systeeminstellingen → Toetsenbord → Sneltoetsen → Services**.

---

## Shortcuts app

Dinky registreert een actie **Afbeeldingen comprimeren** voor de Snelkoppelingen-app. Gebruik het om Finder-bestanden of andere acties via Dinky door te sturen met een gekozen formaat - dezelfde engine als in-app-compressie (respecteert instellingen voor slimme kwaliteit, formaat wijzigen en metagegevens).

---

## Privacy & safety

- Alles draait **lokaal**. Geen uploads, geen telemetrie, geen account.
- **Crashrapporten** worden alleen verzonden als *u* daarvoor kiest: via de post-crash-prompt, het menu 'Een bug rapporteren...' of het foutdetailblad. Als je in Systeeminstellingen hebt aangegeven dat je macOS-diagnoses wilt delen, levert Apple namens jou ook geanonimiseerde crashgegevens aan Dinky via MetricKit, zonder dat er extra gegevens je Mac verlaten.
- De encoders (`cwebp`, `avifenc`, `oxipng`, plus de ingebouwde PDF- en AVFoundation-videopijplijnen van Apple) worden in de app geleverd en lezen uw bestanden rechtstreeks.
- Originelen worden standaard bewaard. *Originelen naar de prullenbak verplaatsen na het comprimeren* is mogelijk via **Instellingen → Algemeen**.
- *Overslaan als besparingen hieronder* (standaard uitgeschakeld) beschermt reeds gestroomlijnde bestanden tegen hercodering voor niets.
- *Metagegevens verwijderen* in elke voorinstelling verwijdert EXIF, GPS, camera-informatie en kleurprofielen. De moeite waard voordat u foto's op internet publiceert.

---

## Troubleshooting

**Er is een bestand verschenen dat groter is dan het origineel.**
Dinky behoudt in plaats daarvan het origineel. Je ziet *"Kan deze niet kleiner maken. Het origineel behouden."* in de rij.

**Er is een bestand overgeslagen.**
Ofwel was het al erg klein (onder uw drempelwaarde *Overslaan als besparing onder*), ofwel kon de encoder het niet lezen. Klik op de rij voor details.

**Een video duurt lang.**
Het opnieuw coderen van video is CPU-zwaar. De instelling *Batchsnelheid* in **Instellingen → Algemeen** bepaalt hoeveel bestanden tegelijk worden uitgevoerd. Zet deze instelling op **Snel** als uw Mac andere dingen doet.

**Mijn PDF verloor tekstselectie / hyperlinks.**
Je hebt *Flatten (kleinste)* gebruikt. Schakel de PDF-uitvoer van de voorinstelling naar *Tekst en links behouden* en voer deze opnieuw uit. Flatten wint altijd op maat; behouden wint altijd op bruikbaarheid.

**Klik met de rechtermuisknop op 'Comprimeren met Dinky' wordt niet weergegeven.**
Open Dinky één keer na installatie, zodat macOS de service registreert. Als het nog steeds niet verschijnt, schakel het dan in **Systeeminstellingen → Toetsenbord → Sneltoetsen → Services → Bestanden en mappen**.

**Waarom voert Dinky geen JPEG uit?**
WebP en AVIF zijn absoluut beter dan JPEG: dezelfde visuele kwaliteit, kleiner bestand en overal ondersteund waar het ertoe doet. Als uw platform een ​​`.jpg` vereist, probeer dan eerst WebP; het wordt nu bijna universeel geaccepteerd. Als u een plaats tegenkomt die het echt afwijst, neem dan contact met ons op en laat het ons weten.

---

## Get in touch

- Site: [dinkyfiles.com](https://dinkyfiles.com)
- Code en problemen: [github.com/heyderekj/dinky](https://github.com/heyderekj/dinky)
- E-mail: [help@dinkyfiles.com](mailto:help@dinkyfiles.com)

Gebouwd door Derek Castelli. Suggesties, bugs en "zou het ook kunnen..." zijn allemaal welkom.
