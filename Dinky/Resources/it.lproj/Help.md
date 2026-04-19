# Welcome

Dinky rende i file dinky. Inserisci qualcosa e prendi una versione più piccola: stesso aspetto, meno peso.

Funziona su **immagini** (JPEG, PNG, WebP, AVIF, TIFF, BMP), **video** (MP4, MOV, M4V) e **PDF**.

Tutto accade sul tuo Mac. Non viene caricato nulla.

---

## Quick start

1. Trascina un file (o una pila di file) sulla finestra di Dinky.
2. Guarda il conteggio scendere.
3. Trova le copie più piccole accanto agli originali (impostazione predefinita), nella cartella Download o in una cartella di tua scelta.

Questo è tutto. Le impostazioni predefinite sono buone. Continua a leggere se vuoi piegarli al tuo volere.

---

## Ways to compress

Non è necessario aprire prima l'app. Scegli quello che si adatta al tuo modo di lavorare.

- **Trascina e rilascia** sulla finestra Dinky o sull'icona del Dock.
- **Apri file…** — `{{SK_OPEN_FILES}}` per scegliere da un foglio.
- **Compressione degli appunti**: `{{SK_PASTE}}` incolla un **file** supportato copiato nel Finder (immagini, video, PDF) o dati di **immagine grezza** (PNG/TIFF da screenshot o browser).
- **Fai clic con il pulsante destro del mouse su Finder → Servizi → Comprimi con Dinky**: funziona su selezioni di qualsiasi dimensione.
- **Guarda una cartella**: Dinky comprime tutto ciò che di nuovo arriva al suo interno. (Vedi *Cartelle esaminate* di seguito.)
- **Azione rapida**: assegna una scorciatoia da tastiera a "Comprimi con Dinky" in Impostazioni di sistema → Tastiera → Scorciatoie da tastiera → Servizi.

---

## Where files go

Impostalo una volta in **Impostazioni → Output**.

- **Stessa cartella dell'originale** *(predefinito)*: mantiene le cose in ordine e in locale.
- **Cartella Download**: utile se elabori molto da email o messaggi.
- **Cartella personalizzata…**: punta Dinky ovunque.

### Filenames

- **Aggiungi "-dinky"** *(predefinito)* — `photo.jpg` diventa `photo-dinky.jpg`. Gli originali sono sicuri.
- **Sostituisci originale**: sovrascrive il file. Combinalo con *Sposta gli originali nel cestino* in **Generale** se desideri un file pulito alla fine.
- **Suffisso personalizzato**: per gli esperti del flusso di lavoro. Usa ciò che si adatta al tuo sistema di archiviazione.

> **Suggerimento professionale:** le preimpostazioni possono sovrascrivere la posizione di salvataggio e il nome file per regola. Usalo per cose come "screenshot → `~/Desktop/web/`, sostituisci originale".

---

## Sidebar & formats

La barra laterale a destra della finestra principale è dove dici a Dinky **cosa** fare.

### Simple sidebar (default)

Tre scelte in linguaggio semplice: **Immagine**, **Video**, **PDF**. Scegline uno per categoria e rilascialo. Dinky individua un codificatore, una qualità e una dimensione sensati.

### Full sidebar

Disattiva **Impostazioni → Generale → Utilizza barra laterale semplice** (o attiva le singole sezioni) per esporre tutti i controlli:

- **Immagini**: formato, suggerimento contenuto (foto/illustrazione/screenshot), larghezza massima, dimensione massima del file.
- **Video**: famiglia di codec (H.264/HEVC/AV1), livello di qualità, strip audio.
- **PDF**: conserva testo e collegamenti o convertili in immagini per ottenere il file più piccolo possibile.

---

## Smart quality

Quando **Qualità intelligente** è attiva (impostazione predefinita per le nuove preimpostazioni), Dinky esamina ciascun file e ne seleziona le impostazioni:

- Le immagini ricevono un codificatore sintonizzato sul loro contenuto (foto occupata rispetto a grafica: interfaccia utente, illustrazione, logo, screenshot).
- I video ottengono un livello in base alla risoluzione e al bitrate di origine, quindi vengono spostati in base al tipo di contenuto: le registrazioni dello schermo e l'animazione/grafica in movimento salgono di un livello in modo che testo e bordi rimangano leggibili. Il filmato della fotocamera viene identificato dalla marca/modello EXIF, quindi non è eccessivamente protetto. Le sorgenti HDR (Dolby Vision, HDR10, HLG) vengono esportate con HEVC per preservare i dettagli dei colori e delle luci; H.264 li appiattirebbe silenziosamente in SDR.
- I PDF ottengono un livello in base alla complessità del documento e al fatto che siano ricchi di testo o di immagini.

Disattivalo in qualsiasi preimpostazione in **Compressione** quando desideri un livello di qualità fisso (Bilanciato/Alto per i video, Basso/Medio/Alto per i PDF), utile per i batch che necessitano di risultati prevedibili.

---

## Presets

Le preimpostazioni sono combinazioni di impostazioni salvate. Costruiscine uno per ogni attività ricorrente.

Esempi che funzionano bene:

- **Immagini Web Hero**: WebP, larghezza massima 1920, aggiungi `-web`.
- **Prodotti del cliente**: WebP, larghezza massima 2560, sostituisci l'originale, salva in "~/Deliverables/".
- **Registrazioni dello schermo**: H.264 bilanciato, strip audio.
- **PDF scansionati**: appiattisci, qualità media, scala di grigi.

Creali in **Impostazioni → Preimpostazioni**. Ciascuno può:

- Applicabile a tutti i media o solo a un tipo (Immagine/Video/PDF).
- Utilizza la propria posizione di salvataggio e la regola del nome file.
- Guarda la propria cartella *(vedi sotto)*.
- Elimina i metadati, disinfetta i nomi dei file, apri la cartella di output una volta terminato.

Cambia la preimpostazione attiva dalla barra laterale in qualsiasi momento.

---

## Watch folders

Trascina i file in una cartella e lascia che Dinky li gestisca in background.

- **Orologio globale** — *Impostazioni → Orologio → Globale*. Utilizza qualunque cosa sia attualmente impostata la barra laterale. Buono per una cartella "in arrivo" o screenshot.
- **Controllo per preimpostazione**: ogni preimpostazione può anche controllare la propria cartella con le proprie regole. Indipendentemente dalla barra laterale: cambia la barra laterale quanto vuoi, la preimpostazione continua a fare il suo dovere.

> **Suggerimento da professionista:** Combina la "cartella delle registrazioni dello schermo" + una preimpostazione che rimuove l'audio e ricodifica in H.264 bilanciato. Premi "⌘⇧5", registra lo schermo, premi stop: Dinky ha un piccolo file pronto prima che tu raggiunga il Finder.

---

## Manual mode

Attiva **Impostazioni → Generali → Modalità manuale** quando desideri il controllo completo.

I file rilasciati non verranno compressi automaticamente. Fai clic con il pulsante destro del mouse su qualsiasi riga per scegliere un formato sul momento, utilizza **File → Comprimi ora** (`{{SK_COMPRESS_NOW}}`) quando la coda è pronta o modifica prima le impostazioni nella barra laterale. Utile quando un batch contiene file molto diversi.

---

## Keyboard shortcuts

Troverai lo stesso elenco in **Impostazioni → Scorciatoie**, quindi non devi scavare in questa pagina.

| Scorciatoia | Azione |
| --- | --- |
| `{{SK_OPEN_FILES}}` | Apri file… |
| `{{SK_PASTE}}` | Comprimi appunti |
| `{{SK_COMPRESS_NOW}}` | Comprimi ora (esegue la coda, particolarmente utile in modalità manuale) |
| `{{SK_CLEAR_ALL}}` | Cancella tutto |
| `{{SK_TOGGLE_SIDEBAR}}` | Attiva/disattiva il formato della barra laterale |
| `{{SK_DELETE}}` | Elimina le righe selezionate |
| `{{SK_SETTINGS}}` | Impostazioni |
| `{{SK_HELP}}` | Questa finestra della Guida |

Aggiungi il tuo per *Comprimi con Dinky* in **Impostazioni di sistema → Tastiera → Scorciatoie da tastiera → Servizi**.

---

## Shortcuts app

Dinky registra un'azione **Comprimi immagini** per l'app Scorciatoie. Usalo per convogliare file del Finder o altre azioni tramite Dinky con un formato scelto: lo stesso motore della compressione in-app (rispetta le impostazioni per qualità intelligente, ridimensionamento e metadati).

---

## Privacy & safety

- Tutto viene eseguito **localmente**. Nessun caricamento, nessuna telemetria, nessun account.
- I **rapporti sugli arresti anomali** vengono inviati solo se *tu* scegli di farlo, tramite il messaggio post-arresto anomalo, il menu "Segnala un bug..." o il foglio dei dettagli dell'errore. Se hai attivato la condivisione diagnostica di macOS nelle Impostazioni di sistema, Apple fornisce anche dati anonimi sugli arresti anomali a Dinky per tuo conto tramite MetricKit, senza che dati aggiuntivi lascino il tuo Mac.
- I codificatori (`cwebp`, `avifenc`, `oxipng`, oltre alle pipeline video PDF e AVFoundation integrate di Apple) vengono forniti all'interno dell'app e leggono direttamente i tuoi file.
- Gli originali vengono conservati per impostazione predefinita. *Spostare gli originali nel cestino dopo la compressione* è un'opzione attivabile in **Impostazioni → Generali**.
- *Salta se il risparmio è riportato di seguito* (disattivato per impostazione predefinita) protegge i file già snelli dalla ricodifica gratuita.
- *Rimuovi metadati* in qualsiasi preimpostazione rimuove EXIF, GPS, informazioni sulla fotocamera e profili colore. Ne vale la pena prima di pubblicare foto sul web.

---

## Troubleshooting

**È uscito un file più grande dell'originale.**
Dinky mantiene invece l'originale. Vedrai *"Impossibile rimpicciolirlo. Mantieni l'originale."* nella riga.

**Un file è stato saltato.**
O era già molto piccolo (sotto la soglia *Salta se il risparmio è inferiore*) oppure il codificatore non è riuscito a leggerlo. Fare clic sulla riga per i dettagli.

**Un video sta impiegando molto tempo.**
La ricodifica video è pesante per la CPU. L'impostazione *Velocità batch* in **Impostazioni → Generale** controlla quanti file vengono eseguiti contemporaneamente: impostala su **Veloce** se il tuo Mac sta facendo altre cose.

**Il mio PDF ha perso la selezione del testo/i collegamenti ipertestuali.**
Hai utilizzato *Appiattisci (il più piccolo)*. Cambia l'output PDF della preimpostazione su *Conserva testo e collegamenti* ed esegui nuovamente. L'appiattimento vince sempre in termini di dimensioni; preservare vince sempre sull’utilità.

**Il clic con il pulsante destro del mouse su "Comprimi con Dinky" non viene visualizzato.**
Apri Dinky una volta dopo l'installazione in modo che macOS registri il servizio. Se ancora non viene visualizzato, abilitalo in **Impostazioni di sistema → Tastiera → Scorciatoie da tastiera → Servizi → File e cartelle**.

**Perché Dinky non stampa JPEG?**
WebP e AVIF sono decisamente migliori di JPEG: stessa qualità visiva, file più piccoli e supportati ovunque sia importante. Se la tua piattaforma richiede un `.jpg`, prova prima WebP; ora è accettato quasi universalmente. Se trovi un posto che lo rifiuta sinceramente, contattaci e faccelo sapere.

---

## Get in touch

- Sito: [dinkyfiles.com](https://dinkyfiles.com)
- Codice e problemi: [github.com/heyderekj/dinky](https://github.com/heyderekj/dinky)
- E-mail: [help@dinkyfiles.com](mailto:help@dinkyfiles.com)

Costruito da Derek Castelli. Suggerimenti, bug e "potrebbe anche fare..." sono tutti benvenuti.
