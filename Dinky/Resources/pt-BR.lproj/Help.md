# Welcome

Dinky torna os arquivos pequenos. Coloque algo e tire uma versão menor - mesma aparência, menos peso.

Funciona em **imagens** (JPEG, PNG, WebP, AVIF, TIFF, BMP), **vídeos** (MP4, MOV, M4V) e **PDFs**.

Tudo acontece no seu Mac. Nada é carregado.

---

## Quick start

1. Arraste um arquivo (ou uma pilha deles) para a janela do Dinky.
2. Observe a contagem diminuir.
3. Encontre as cópias menores ao lado dos originais (padrão), na pasta Downloads ou em uma pasta de sua escolha.

É isso. Os padrões são bons. Continue lendo se quiser dobrá-los à sua vontade.

---

## Ways to compress

Você não precisa abrir o aplicativo primeiro. Escolha o que melhor se adapta ao seu modo de trabalhar.

- **Arraste e solte** na janela do Dinky ou no ícone do Dock.
- **Abrir arquivos…** — `{{SK_OPEN_FILES}}` para escolher em uma planilha.
- **Clipboard Compress** — `{{SK_PASTE}}` cola um **arquivo** compatível copiado no Finder (imagens, vídeos, PDFs) ou dados de **imagem bruta** (PNG/TIFF de capturas de tela ou navegadores).
- **Clique com o botão direito em Finder → Serviços → Compactar com Dinky** — funciona em seleções de qualquer tamanho.
- **Assistir a uma pasta** — Dinky compacta qualquer coisa nova que caia nela. (Veja *Pastas de observação* abaixo.)
- **Ação rápida** — atribua um atalho de teclado para "Compactar com Dinky" em Configurações do sistema → Teclado → Atalhos de teclado → Serviços.

---

## Where files go

Defina isso uma vez em **Configurações → Saída**.

- **Mesma pasta do original** *(padrão)* — mantém tudo organizado e local.
- **Pasta de downloads** — bom se você processa muito e-mail ou mensagens.
- **Pasta personalizada…** — aponte Dinky para qualquer lugar.

### Filenames

- **Anexar "-dinky"** *(padrão)* — `photo.jpg` torna-se `photo-dinky.jpg`. Os originais estão seguros.
- **Substituir original** — substitui o arquivo. Combine com *Mover originais para a lixeira* em **Geral** se desejar um arquivo limpo no final.
- **Sufixo personalizado** — para os criadores de fluxo de trabalho. Use o que for adequado ao seu sistema de arquivamento.

> **Dica profissional:** As predefinições podem substituir o local de salvamento e o nome do arquivo por regra. Use isso para coisas como "capturas de tela → `~/Desktop/web/`, substitua o original".

---

## Sidebar & formats

A barra lateral à direita da janela principal é onde você diz ao Dinky **o que** fazer.

### Simple sidebar (default)

Três opções de linguagem simples: **Imagem**, **Vídeo**, **PDF**. Escolha um por categoria e solte. Dinky descobre um codificador, qualidade e tamanho sensatos.

### Full sidebar

Desative **Configurações → Geral → Usar barra lateral simples** (ou ative seções individuais) para expor todos os controles:

- **Imagens** — formato, dica de conteúdo (foto/ilustração/captura de tela), largura máxima, tamanho máximo do arquivo.
- **Vídeos** — família de codecs (H.264/HEVC/AV1), nível de qualidade, faixa de áudio.
- **PDFs** — preserve texto e links ou nivele imagens para obter o menor arquivo possível.

---

## Smart quality

Quando **Qualidade inteligente** está ativada (padrão para novas predefinições), Dinky inspeciona cada arquivo e escolhe as configurações para ele:

- As imagens recebem um codificador ajustado ao seu conteúdo (foto ocupada versus gráfico - UI, ilustração, logotipo, captura de tela).
- Os vídeos recebem um nível com base na resolução e taxa de bits de origem e, em seguida, são ajustados de acordo com o tipo de conteúdo – gravações de tela e animações/gráficos em movimento sobem um nível para que o texto e as bordas permaneçam legíveis. A filmagem da câmera é identificada pela marca/modelo EXIF, portanto não é superprotegida. Fontes HDR (Dolby Vision, HDR10, HLG) são exportadas com HEVC para preservar cores e destacar detalhes; O H.264 os achataria silenciosamente para SDR.
- Os PDFs recebem uma camada com base na complexidade do documento e se eles priorizam o texto ou muitas imagens.

Desative-o em qualquer predefinição em **Compressão** quando quiser um nível de qualidade fixo (Balanceado/Alto para vídeo, Baixo/Médio/Alto para PDFs) — útil para lotes que precisam de resultados previsíveis.

---

## Presets

As predefinições são combinações salvas de configurações. Crie um para cada tarefa repetida.

Exemplos que funcionam bem:

- **Imagens do Web Hero** — WebP, largura máxima 1920, acrescente `-web`.
- **Entregas do cliente** — WebP, largura máxima de 2560, substitua o original, salve em `~/Deliverables/`.
- **Gravações de tela** — H.264 balanceado, faixa de áudio.
- **PDFs digitalizados** — nivelados, qualidade média, escala de cinza.

Crie-os em **Configurações → Predefinições**. Cada um pode:

- Aplicar a todas as mídias ou apenas um tipo (Imagem/Vídeo/PDF).
- Use seu próprio local de salvamento e regra de nome de arquivo.
- Assista a sua própria pasta *(veja abaixo)*.
- Remova metadados, limpe nomes de arquivos e abra a pasta de saída quando terminar.

Alterne a predefinição ativa na barra lateral a qualquer momento.

---

## Watch folders

Solte os arquivos em uma pasta e deixe o Dinky cuidar deles em segundo plano.

- **Relógio global** — *Configurações → Assistir → Global*. Usa o que quer que a barra lateral esteja configurada no momento. Bom para uma pasta de "entrada" ou captura de tela.
- **Visualização por predefinição** — cada predefinição também pode monitorar sua própria pasta com suas próprias regras. Independentemente da barra lateral – altere a barra lateral o quanto quiser, a predefinição ainda funciona.

> **Dica profissional:** Combine "pasta de gravações de tela" + uma predefinição que retira o áudio e recodifica para H.264 Balanceado. Pressione `⌘⇧5`, grave a tela, pressione parar – Dinky tem um pequeno arquivo pronto antes de você chegar ao Finder.

---

## Manual mode

Ative **Configurações → Geral → Modo manual** quando desejar controle total.

Os arquivos inseridos não serão compactados automaticamente. Clique com o botão direito em qualquer linha para escolher um formato imediatamente, use **Arquivo → Compactar agora** (`{{SK_COMPRESS_NOW}}`) quando a fila estiver pronta ou altere as configurações na barra lateral primeiro. Útil quando um lote contém arquivos muito diferentes.

---

## Keyboard shortcuts

Você encontrará a mesma lista em **Configurações → Atalhos** para não precisar vasculhar esta página.

| Atalho | Ação |
| --- | --- |
| `{{SK_OPEN_FILES}}` | Abra arquivos… |
| `{{SK_PASTE}}` | Comprimir área de transferência |
| `{{SK_COMPRESS_NOW}}` | Compress Now (executa a fila — especialmente útil no modo Manual) |
| `{{SK_CLEAR_ALL}}` | Limpar tudo |
| `{{SK_TOGGLE_SIDEBAR}}` | Alternar formato da barra lateral |
| `{{SK_DELETE}}` | Excluir linhas selecionadas |
| `{{SK_SETTINGS}}` | Configurações |
| `{{SK_HELP}}` | Esta janela de Ajuda |

Adicione o seu próprio para *Compactar com Dinky* em **Configurações do sistema → Teclado → Atalhos de teclado → Serviços**.

---

## Shortcuts app

Dinky registra uma ação **Compactar imagens** para o aplicativo Shortcuts. Use-o para canalizar arquivos do Finder ou outras ações através do Dinky com um formato escolhido - o mesmo mecanismo da compactação no aplicativo (respeita as configurações de qualidade inteligente, redimensionamento e metadados).

---

## Privacy & safety

- Tudo funciona **localmente**. Sem uploads, sem telemetria, sem conta.
- **Relatórios de falhas** são enviados apenas se *você* optar por fazê-lo — por meio do prompt pós-travamento, do menu "Relatar um bug…" ou da folha de detalhes do erro. Se você optou pelo compartilhamento de diagnóstico do macOS nas configurações do sistema, a Apple também fornece dados anônimos de falhas ao Dinky em seu nome por meio do MetricKit, sem que dados adicionais saiam do seu Mac.
- Os codificadores (`cwebp`, `avifenc`, `oxipng`, além dos pipelines de vídeo PDF e AVFoundation integrados da Apple) são fornecidos dentro do aplicativo e leem seus arquivos diretamente.
- Os originais são mantidos por padrão. *Mover originais para a lixeira após compactar* é opcional, em **Configurações → Geral**.
- *Pular se a economia abaixo* (desativado por padrão) protege arquivos já enxutos de serem recodificados por nada.
- *Retirar metadados* em qualquer predefinição remove EXIF, GPS, informações da câmera e perfis de cores. Vale a pena antes de publicar fotos na web.

---

## Troubleshooting

**Um arquivo saiu maior que o original.**
Dinky mantém o original. Você verá *"Não foi possível diminuir este tamanho. Mantendo o original."* na linha.

**Um arquivo foi ignorado.**
Ou já era muito pequeno (abaixo do limite *Pular se a economia estiver abaixo*) ou o codificador não conseguiu lê-lo. Clique na linha para obter detalhes.

**Um vídeo está demorando muito.**
A recodificação de vídeo exige muito da CPU. A configuração *Velocidade do lote* em **Configurações → Geral** controla quantos arquivos são executados de uma vez. Coloque-a em **Rápido** se o seu Mac estiver fazendo outras coisas.

**Meu PDF perdeu seleção de texto/hiperlinks.**
Você usou *Achatar (menor)*. Mude a saída PDF da predefinição para *Preservar texto e links* e execute novamente. Flatten sempre ganha em tamanho; preservar sempre ganha em utilidade.

**Clique com o botão direito em "Compactar com Dinky" e não aparece.**
Abra o Dinky uma vez após a instalação para que o macOS registre o serviço. Se ainda assim não aparecer, habilite-o em **Configurações do Sistema → Teclado → Atalhos de Teclado → Serviços → Arquivos e Pastas**.

**Por que o Dinky não gera JPEG?**
WebP e AVIF são estritamente melhores que JPEG – mesma qualidade visual, arquivo menor e suporte em todos os lugares importantes. Se a sua plataforma requer um `.jpg`, tente primeiro o WebP; é aceito quase universalmente agora. Se você encontrar um lugar que realmente o rejeita, entre em contato e nos avise.

---

## Get in touch

- Site: [dinkyfiles.com](https://dinkyfiles.com)
- Código e problemas: [github.com/heyderekj/dinky](https://github.com/heyderekj/dinky)
- E-mail: [help@dinkyfiles.com](mailto:help@dinkyfiles.com)

Construído por Derek Castelli. Sugestões, bugs e "também poderia servir..." são bem-vindos.
