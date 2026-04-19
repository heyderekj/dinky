# Welcome

Dinky hace que los archivos sean pequeños. Introduzca algo y obtenga una versión más pequeña: el mismo aspecto, menos peso.

Funciona con **imágenes** (JPEG, PNG, WebP, AVIF, TIFF, BMP), **vídeos** (MP4, MOV, M4V) y **PDF**.

Todo sucede en tu Mac. No se carga nada.

---

## Quick start

1. Arrastra un archivo (o un montón de ellos) a la ventana de Dinky.
2. Observe cómo baja la cuenta.
3. Busque las copias más pequeñas junto a los originales (predeterminado), en su carpeta de Descargas o en la carpeta que elija.

Eso es todo. Los valores predeterminados son buenos. Continúe leyendo si quiere someterlos a su voluntad.

---

## Ways to compress

No es necesario que abras la aplicación primero. Elija el que mejor se adapte a su forma de trabajar.

- **Arrastra y suelta** en la ventana de Dinky o en el ícono del Dock.
- **Abrir Archivos…** — `{{SK_OPEN_FILES}}` para seleccionar de una hoja.
- **Comprimir portapapeles**: `{{SK_PASTE}}` pega un **archivo** compatible copiado en Finder (imágenes, videos, PDF) o datos de **imagen sin procesar** (PNG/TIFF de capturas de pantalla o navegadores).
- **Haga clic derecho en Finder → Servicios → Comprimir con Dinky**: funciona en selecciones de cualquier tamaño.
- **Mira una carpeta**: Dinky comprime todo lo nuevo que llega a ella. (Consulte *Carpetas vigiladas* a continuación).
- **Acción rápida**: asigne un método abreviado de teclado para "Comprimir con Dinky" en Configuración del sistema → Teclado → Atajos de teclado → Servicios.

---

## Where files go

Establezca esto una vez en **Configuración → Salida**.

- **Misma carpeta que la original** *(predeterminada)*: mantiene todo ordenado y local.
- **Carpeta de descargas**: buena si procesas mucho desde correo electrónico o mensajes.
- **Carpeta personalizada...**: apunta a Dinky a cualquier lugar.

### Filenames

- **Agregar "-dinky"** *(predeterminado)* — `photo.jpg` se convierte en `photo-dinky.jpg`. Los originales están a salvo.
- **Reemplazar original**: sobrescribe el archivo. Combínelo con *Mover originales a la papelera* en **General** si desea un archivo limpio al final.
- **Sufijo personalizado**: para los que modifican el flujo de trabajo. Utilice lo que se adapte a su sistema de archivo.

> **Consejo profesional:** Los ajustes preestablecidos pueden anular la ubicación de guardado y el nombre de archivo por regla. Úselo para cosas como "capturas de pantalla → `~/Desktop/web/`, reemplazar el original".

---

## Sidebar & formats

La barra lateral a la derecha de la ventana principal es donde le dices a Dinky **qué** hacer.

### Simple sidebar (default)

Tres opciones de lenguaje sencillo: **Imagen**, **Video**, **PDF**. Elija uno por categoría y suéltelo. Dinky descubre un codificador, una calidad y un tamaño sensatos.

### Full sidebar

Desactive **Configuración → General → Usar barra lateral simple** (o active secciones individuales) para exponer cada control:

- **Imágenes**: formato, sugerencia de contenido (foto/ilustración/captura de pantalla), ancho máximo, tamaño máximo de archivo.
- **Vídeos**: familia de códecs (H.264 / HEVC / AV1), nivel de calidad, banda de audio.
- **PDF**: conserva texto y enlaces, o aplana en imágenes para obtener el archivo más pequeño posible.

---

## Smart quality

Cuando **Calidad inteligente** está activada (predeterminada para nuevos ajustes preestablecidos), Dinky inspecciona cada archivo y selecciona la configuración para él:

- Las imágenes obtienen un codificador adaptado a su contenido (fotografía ocupada frente a gráfico: interfaz de usuario, ilustración, logotipo, captura de pantalla).
- Los videos obtienen un nivel basado en la resolución y la tasa de bits de la fuente, luego se modifican según el tipo de contenido: las grabaciones de pantalla y las animaciones/gráficos en movimiento suben un nivel para que el texto y los bordes sigan siendo legibles. Las imágenes de la cámara se identifican según la marca/modelo EXIF, por lo que no están sobreprotegidas. Las fuentes HDR (Dolby Vision, HDR10, HLG) se exportan con HEVC para preservar el color y resaltar los detalles; H.264 los aplanaría silenciosamente a SDR.
- Los archivos PDF obtienen un nivel basado en la complejidad del documento y si tienen primero texto o imágenes.

Desactívelo en cualquier ajuste preestablecido en **Compresión** cuando desee un nivel de calidad fijo (Equilibrado/Alto para video, Bajo/Medio/Alto para archivos PDF), útil para lotes que necesitan resultados predecibles.

---

## Presets

Los ajustes preestablecidos son combinaciones guardadas de configuraciones. Construya uno para cada tarea repetitiva.

Ejemplos que funcionan bien:

- **Imágenes principales de Web** — WebP, ancho máximo 1920, agregar `-web`.
- **Entregables del cliente** — WebP, ancho máximo 2560, reemplazar el original, guardar en `~/Deliverables/`.
- **Grabaciones de pantalla** — H.264 balanceado, audio en banda.
- **PDF escaneados**: aplanar, calidad media, escala de grises.

Créelos en **Configuración → Presets**. Cada uno puede:

- Aplicar a todos los medios o solo a un tipo (Imagen/Video/PDF).
- Utilice su propia ubicación para guardar y regla de nombre de archivo.
- Mirar su propia carpeta *(ver más abajo)*.
- Elimina metadatos, desinfecta nombres de archivos, abre la carpeta de salida cuando hayas terminado.

Cambie el ajuste preestablecido activo desde la barra lateral en cualquier momento.

---

## Watch folders

Suelta los archivos en una carpeta y deja que Dinky los maneje en segundo plano.

- **Vigilancia global** — *Configuración → Vigilancia → Global*. Utiliza lo que sea que esté configurada actualmente la barra lateral. Bueno para una carpeta "entrante" o de captura de pantalla.
- **Visualización por preajuste**: cada preajuste también puede observar su propia carpeta con sus propias reglas. Independientemente de la barra lateral: cambia la barra lateral todo lo que quieras, el ajuste preestablecido seguirá funcionando.

> **Consejo profesional:** Combine la "carpeta de grabaciones de pantalla" + un ajuste preestablecido que elimina el audio y lo vuelve a codificar a H.264 balanceado. Presiona `⌘⇧5`, graba la pantalla, presiona detener: Dinky tiene un pequeño archivo listo antes de llegar al Finder.

---

## Manual mode

Active **Configuración → General → Modo manual** cuando desee un control total.

Los archivos ingresados ​​no se comprimirán automáticamente. Haga clic derecho en cualquier fila para elegir un formato en el momento, use **Archivo → Comprimir ahora** (`{{SK_COMPRESS_NOW}}`) cuando la cola esté lista, o cambie primero la configuración en la barra lateral. Útil cuando un lote contiene archivos muy diferentes.

---

## Keyboard shortcuts

Encontrarás la misma lista en **Configuración → Accesos directos** para que no tengas que buscar en esta página.

| Atajo | Acción |
| --- | --- |
| `{{SK_OPEN_FILES}}` | Abrir archivos… |
| `{{SK_PASTE}}` | Comprimir portapapeles |
| `{{SK_COMPRESS_NOW}}` | Comprimir ahora (ejecuta la cola, especialmente útil en modo manual) |
| `{{SK_CLEAR_ALL}}` | Borrar todo |
| `{{SK_TOGGLE_SIDEBAR}}` | Alternar barra lateral de formato |
| `{{SK_DELETE}}` | Eliminar filas seleccionadas |
| `{{SK_SETTINGS}}` | Configuración |
| `{{SK_HELP}}` | Esta ventana de Ayuda |

Agregue el suyo propio para *Comprimir con Dinky* en **Configuración del sistema → Teclado → Atajos de teclado → Servicios**.

---

## Shortcuts app

Dinky registra una acción **Comprimir imágenes** para la aplicación Atajos. Úselo para canalizar archivos del Finder u otras acciones a través de Dinky con un formato elegido: el mismo motor que la compresión en la aplicación (respeta la configuración de calidad inteligente, cambio de tamaño y metadatos).

---

## Privacy & safety

- Todo se ejecuta **localmente**. Sin cargas, sin telemetría, sin cuenta.
- Los **informes de fallos** solo se envían si *usted* así lo desea: a través del mensaje posterior al fallo, el menú "Informar un error..." o la hoja de detalles del error. Si ha optado por compartir diagnósticos de macOS en Configuración del sistema, Apple también entrega datos de fallos anónimos a Dinky en su nombre a través de MetricKit, sin que salgan datos adicionales de su Mac.
- Los codificadores (`cwebp`, `avifenc`, `oxipng`, además de los canales de video PDF y AVFoundation integrados de Apple) se envían dentro de la aplicación y leen sus archivos directamente.
- Los originales se conservan por defecto. *Mover los originales a la papelera después de comprimirlos* es una opción opcional, en **Configuración → General**.
- *Omitir si los ahorros se indican a continuación* (desactivado de forma predeterminada) protege los archivos que ya están optimizados para que no se vuelvan a codificar de forma gratuita.
- *Eliminar metadatos* en cualquier ajuste preestablecido elimina EXIF, GPS, información de la cámara y perfiles de color. Vale la pena antes de publicar fotos en la web.

---

## Troubleshooting

**Un archivo salió más grande que el original.**
Dinky se queda con el original. Verás *"No se pudo hacer este más pequeño. Conservando el original."* en la fila.

**Se omitió un archivo.**
O ya era muy pequeño (por debajo de su umbral de *Omitir si los ahorros son inferiores*), o el codificador no pudo leerlo. Haga clic en la fila para obtener más detalles.

**Un vídeo está tardando mucho.**
La recodificación de vídeo consume mucha CPU. La configuración de *Velocidad de lote* en **Configuración → General** controla cuántos archivos se ejecutan a la vez; colócala en **Rápido** si tu Mac está haciendo otras cosas.

**Mi PDF perdió la selección de texto/hipervínculos.**
Usaste *Aplanar (más pequeño)*. Cambie la salida PDF del ajuste preestablecido a *Conservar texto y enlaces* y vuelva a ejecutarlo. Aplanar siempre gana en tamaño; preservar siempre gana en utilidad.

**No aparece "Comprimir con Dinky" al hacer clic derecho.**
Abra Dinky una vez después de la instalación para que macOS registre el Servicio. Si aún no aparece, habilítelo en **Configuración del sistema → Teclado → Atajos de teclado → Servicios → Archivos y carpetas**.

**¿Por qué Dinky no genera JPEG?**
WebP y AVIF son estrictamente mejores que JPEG: la misma calidad visual, archivos más pequeños y compatibles en todos los lugares importantes. Si su plataforma requiere un `.jpg`, pruebe primero con WebP; ahora se acepta casi universalmente. Si llegas a un lugar que realmente lo rechaza, ponte en contacto y háznoslo saber.

---

## Get in touch

- Sitio: [dinkyfiles.com](https://dinkyfiles.com)
- Código y problemas: [github.com/heyderekj/dinky](https://github.com/heyderekj/dinky)
- Correo electrónico: [help@dinkyfiles.com](mailto:help@dinkyfiles.com)

Construido por Derek Castelli. Sugerencias, errores y "¿podría funcionar también?" son bienvenidos.
