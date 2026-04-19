# Welcome

Dinky, dosyaları önemsiz hale getirir. İçine bir şey bırakın, daha küçük bir versiyonunu çıkarın; aynı görünüm, daha az ağırlık.

**Resimler** (JPEG, PNG, WebP, AVIF, TIFF, BMP), **videolar** (MP4, MOV, M4V) ve **PDF'ler** üzerinde çalışır.

Her şey Mac'inizde gerçekleşir. Hiçbir şey yüklenmedi.

---

## Quick start

1. Bir dosyayı (veya bir yığınını) Dinky'nin penceresine sürükleyin.
2. Sayımın azalmasını izleyin.
3. Orijinallerin yanında (varsayılan), İndirilenler klasörünüzde veya seçtiğiniz bir klasörde daha küçük kopyaları bulun.

İşte bu. Varsayılanlar iyidir. Onları kendi isteğinize göre bükmek istiyorsanız okumaya devam edin.

---

## Ways to compress

Önce uygulamayı açmanıza gerek yok. Hangisi çalışma şeklinize uyuyorsa onu seçin.

- **Dinky penceresine veya Dock simgesine **sürükleyip bırakın**.
- **Dosyaları Aç…** — Bir sayfadan seçmek için `{{SK_OPEN_FILES}}`.
- **Pano Sıkıştırma** — `{{SK_PASTE}}` Finder'da kopyalanan desteklenen bir **dosyayı** (resimler, videolar, PDF'ler) veya **ham resim** verilerini (ekran görüntülerinden veya tarayıcılardan PNG/TIFF) yapıştırır.
- **Finder'da sağ tıklayın → Hizmetler → Dinky ile Sıkıştır** — her boyuttaki seçimlerde çalışır.
- **Bir klasörü izleyin** — Dinky, içine giren yeni her şeyi sıkıştırır. (Aşağıdaki *İzleme klasörlerine* bakın.)
- **Hızlı Eylem** — Sistem Ayarları → Klavye → Klavye Kısayolları → Hizmetler bölümünde "Dinky ile Sıkıştır" seçeneğine bir klavye kısayolu atayın.

---

## Where files go

Bunu **Ayarlar → Çıkış**'ta bir kez ayarlayın.

- **Orijinalle aynı klasör** *(varsayılan)* — işleri düzenli ve yerel tutar.
- **İndirilenler klasörü** — e-posta veya mesajlardan çok fazla işlem yapıyorsanız iyi bir seçenektir.
- **Özel klasör…** — Dinky'yi herhangi bir yere yönlendirin.

### Filenames

- **"-dinky" ekle** *(varsayılan)* — `photo.jpg`, `photo-dinky.jpg` olur. Orijinaller güvenlidir.
- **Orijinali değiştir** — dosyanın üzerine yazar. Sonunda temiz bir dosya istiyorsanız **Genel** bölümündeki *Orijinalleri çöp kutusuna taşı* seçeneğiyle birleştirin.
- **Özel son ek** — iş akışıyla ilgilenenler için. Dosyalama sisteminize uygun olanı kullanın.

> **Profesyonel ipucu:** Ön ayarlar, kural başına kaydetme konumunu ve dosya adını geçersiz kılabilir. Bunu "ekran görüntüleri → `~/Desktop/web/`, orijinali değiştir" gibi şeyler için kullanın.

---

## Sidebar & formats

Ana pencerenin sağındaki kenar çubuğu Dinky'ye **ne** yapması gerektiğini söylediğiniz yerdir.

### Simple sidebar (default)

Üç sade dil seçeneği: **Resim**, **Video**, **PDF**. Kategori başına bir tane seçin ve bırakın. Dinky mantıklı bir kodlayıcı, kalite ve boyut buluyor.

### Full sidebar

Her kontrolü ortaya çıkarmak için **Ayarlar → Genel → Basit kenar çubuğunu kullan** seçeneğini kapatın (veya ayrı bölümleri açın):

- **Resimler** — format, içerik ipucu (fotoğraf / illüstrasyon / ekran görüntüsü), maksimum genişlik, maksimum dosya boyutu.
- **Videolar** — codec ailesi (H.264 / HEVC / AV1), kalite katmanı, şerit ses.
- **PDF'ler** — metni ve bağlantıları koruyun veya mümkün olan en küçük dosya için görüntüleri düzleştirin.

---

## Smart quality

**Akıllı kalite** açıkken (yeni ön ayarlar için varsayılan), Dinky her dosyayı inceler ve bunun için ayarları seçer:

- Görüntüler, içeriklerine göre ayarlanmış bir kodlayıcıya sahiptir (yoğun fotoğraf ve grafik — kullanıcı arayüzü, illüstrasyon, logo, ekran görüntüsü).
- Videolar, çözünürlüğe ve kaynak bit hızına göre bir katmana sahip olur, ardından içerik türüne göre yönlendirilir; ekran kayıtları ve animasyon/hareketli grafikler bir katman yukarı çıkar, böylece metin ve kenarlar okunabilir kalır. Kamera görüntüleri EXIF ​​marka/modeline göre tanımlandığından aşırı korunmaz. HDR kaynakları (Dolby Vision, HDR10, HLG), rengi korumak ve ayrıntıları vurgulamak için HEVC ile dışa aktarılır; H.264 bunları sessizce SDR'ye düzleştirecektir.
- PDF'ler, belgenin karmaşıklığına ve öncelikli metin mi yoksa görüntü ağırlıklı mı olduklarına bağlı olarak bir katmana sahiptir.

Sabit kalitede bir katman (Video için Dengeli / Yüksek, PDF'ler için Düşük / Orta / Yüksek) istediğinizde **Sıkıştırma** altındaki herhangi bir ön ayarda bu özelliği kapatın; öngörülebilir sonuçlara ihtiyaç duyan gruplar için kullanışlıdır.

---

## Presets

Ön ayarlar, kaydedilmiş ayar kombinasyonlarıdır. Tekrarlanan her görev için bir tane oluşturun.

İyi çalışan örnekler:

- **Web kahramanı görüntüleri** — WebP, maksimum genişlik 1920, "-web" ekleyin.
- **Müşteri teslimatları** — WebP, maksimum genişlik 2560, orijinali değiştirin, "~/Deliverables/" dosyasına kaydedin.
- **Ekran kayıtları** — H.264 Dengeli, şerit ses.
- **Taranan PDF'ler** — düzleştirilmiş, orta kalitede, gri tonlamalı.

Bunları **Ayarlar → Ön Ayarlar** bölümünde oluşturun. Her biri şunları yapabilir:

- Tüm ortamlara veya yalnızca tek bir türe (Resim / Video / PDF) uygulayın.
- Kendi kaydetme konumunu ve dosya adı kuralını kullanın.
- Kendi klasörünü izleyin *(aşağıya bakın)*.
- Meta verileri soyun, dosya adlarını temizleyin, işiniz bittiğinde çıktı klasörünü açın.

Etkin ön ayarı istediğiniz zaman kenar çubuğundan değiştirebilirsiniz.

---

## Watch folders

Dosyaları bir klasöre bırakın ve Dinky'nin bunları arka planda işlemesine izin verin.

- **Global izleme** — *Ayarlar → İzle → Global*. Kenar çubuğunun o anda ayarlı olduğu şeyi kullanır. "Gelen" veya ekran görüntüsü klasörü için iyidir.
- **Ön ayar başına izleme** — her ön ayar, kendi kurallarıyla kendi klasörünü de izleyebilir. Kenar çubuğundan bağımsız olarak kenar çubuğunu istediğiniz kadar değiştirin, ön ayar yine de işini yapar.

> **Profesyonel ipucu:** "Ekran kayıtları klasörü" + sesi kesen ve H.264 Dengeli olarak yeniden kodlayan bir ön ayarı birleştirin. '⌘⇧5' tuşuna basın, ekran kaydı yapın, durdur tuşuna basın — Finder'a ulaşmadan önce Dinky'nin küçük bir dosyası hazır.

---

## Manual mode

Tam kontrol istediğinizde **Ayarlar → Genel → Manuel modu** açın.

Bırakılan dosyalar otomatik olarak sıkıştırılmaz. Hemen bir format seçmek için herhangi bir satıra sağ tıklayın, sıra hazır olduğunda **Dosya → Şimdi Sıkıştır** (`{{SK_COMPRESS_NOW}}`) seçeneğini kullanın veya önce kenar çubuğundaki ayarları değiştirin. Bir toplu iş çok farklı dosyalar içerdiğinde kullanışlıdır.

---

## Keyboard shortcuts

Aynı listeyi **Ayarlar → Kısayollar**'da da bulabilirsiniz, böylece bu sayfayı ayrıntılı olarak incelemenize gerek kalmaz.

| Kısayol | Eylem |
| --- | --- |
| `{{SK_OPEN_FILES}}` | Dosyaları aç… |
| `{{SK_PASTE}}` | Pano Sıkıştırma |
| `{{SK_COMPRESS_NOW}}` | Şimdi Sıkıştır (sırayı çalıştırır; özellikle Manuel modda kullanışlıdır) |
| `{{SK_CLEAR_ALL}}` | Tümünü Temizle |
| `{{SK_TOGGLE_SIDEBAR}}` | Biçim kenar çubuğunu değiştir |
| `{{SK_DELETE}}` | Seçilen satırları sil |
| `{{SK_SETTINGS}}` | Ayarlar |
| `{{SK_HELP}}` | Bu Yardım penceresi |

**Sistem Ayarları → Klavye → Klavye Kısayolları → Hizmetler** bölümünde *Dinky ile Sıkıştır* için kendinizinkini ekleyin.

---

## Shortcuts app

Dinky, Kısayollar uygulaması için bir **Resimleri Sıkıştır** işlemini kaydeder. Finder dosyalarını veya diğer eylemleri Dinky aracılığıyla seçilen bir formatla yönlendirmek için kullanın; uygulama içi sıkıştırmayla aynı motor (akıllı kalite, yeniden boyutlandırma ve meta veriler için Ayarlar'a saygı duyar).

---

## Privacy & safety

- Her şey **yerel olarak** çalışır. Yükleme yok, telemetri yok, hesap yok.
- **Kilitlenme raporları** yalnızca *sizin*, kilitlenme sonrası istemi, "Hata Bildir..." menüsü veya hata ayrıntı sayfası aracılığıyla gönderilmesini tercih ederseniz gönderilir. Sistem Ayarlarında macOS teşhis paylaşımını seçtiyseniz Apple, Mac'inizden hiçbir ek veri ayrılmadan MetricKit aracılığıyla sizin adınıza Dinky'ye anonimleştirilmiş kilitlenme verilerini de iletir.
- Kodlayıcılar ("cwebp", "avifenc", "oxipng" artı Apple'ın yerleşik PDF ve AVFoundation video hatları) uygulamanın içine gönderilir ve dosyalarınızı doğrudan okur.
- Orijinaller varsayılan olarak saklanır. **Ayarlar → Genel** bölümünde *Orijinalleri sıkıştırdıktan sonra çöp kutusuna taşı* seçeneği isteğe bağlıdır.
- *Aşağıdaki tasarrufları atla* (varsayılan olarak kapalıdır), zaten zayıf olan dosyaların boşuna yeniden kodlanmasını önler.
- Herhangi bir ön ayardaki *meta verileri soyun* EXIF, GPS, kamera bilgileri ve renk profillerini kaldırır. Fotoğrafları internette yayınlamadan önce buna değer.

---

## Troubleshooting

**Orijinalinden daha büyük bir dosya çıktı.**
Dinky bunun yerine orijinali saklıyor. Satırda *"Bunu daha küçük hale getiremedim. Orijinali korunuyor."* ifadesini göreceksiniz.

**Bir dosya atlandı.**
Ya zaten çok küçüktü (*Tasarruflar aşağıdaysa atla* eşiğinizin altında) ya da kodlayıcı bunu okuyamıyordu. Ayrıntılar için satıra tıklayın.

**Bir video uzun sürüyor.**
Videonun yeniden kodlanması CPU açısından ağırdır. **Ayarlar → Genel** bölümündeki *Toplu iş hızı* ayarı aynı anda kaç dosyanın çalıştırılacağını kontrol eder; Mac'iniz başka şeyler yapıyorsa bu ayarı **Hızlı**'ya bırakın.

**PDF'imde metin seçimi/köprü bağlantıları kayboldu.**
*Düzleştir (en küçük)* seçeneğini kullandınız. Hazır ayarın PDF çıktısını *Metni ve bağlantıları koru* olarak değiştirin ve yeniden çalıştırın. Düzleştirme her zaman boyut açısından kazanır; korumak her zaman yararlılık açısından kazanır.

**"Dinky ile Sıkıştır"a sağ tıklayınca görünmüyor.**
MacOS'un Hizmeti kaydetmesi için kurulumdan sonra Dinky'yi bir kez açın. Hâlâ görünmüyorsa **Sistem Ayarları → Klavye → Klavye Kısayolları → Hizmetler → Dosyalar ve Klasörler** bölümünden etkinleştirin.

**Dinky neden JPEG çıktısı vermiyor?**
WebP ve AVIF, JPEG'den kesinlikle daha iyidir; aynı görsel kalite, daha küçük dosya ve önemli olan her yerde desteklenir. Platformunuz ".jpg" gerektiriyorsa önce WebP'yi deneyin; artık neredeyse evrensel olarak kabul ediliyor. Gerçekten reddeden bir yere rastlarsanız bizimle iletişime geçin ve bize bildirin.

---

## Get in touch

- Site: [dinkyfiles.com](https://dinkyfiles.com)
- Kod ve sorunlar: [github.com/heyderekj/dinky](https://github.com/heyderekj/dinky)
- E-posta: [help@dinkyfiles.com](mailto:help@dinkyfiles.com)

Derek Castelli tarafından yaptırılmıştır. Öneriler, hatalar ve "bu da yapılabilir mi?" gibi soruların tümü memnuniyetle karşılanır.
