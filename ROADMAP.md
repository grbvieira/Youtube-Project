# Roadmap

Plano de evolucao do YouTube PiP. Atualizado em 2026-11-09.

## Concluido

### Fase 1 — Estabilidade
- [x] `@MainActor` no `BrowserViewModel` e no `NowPlayingController`; checagem estrita de concorrencia (`SWIFT_STRICT_CONCURRENCY = complete`).
- [x] `AudioSessionManager`: categoria `.playback` na abertura sem ativar a sessao (nao corta outros apps); interrupcoes (ligacoes) e pausa ao desconectar o fone.
- [x] Estado do PiP vindo de eventos reais, nao de texto de mensagem.
- [x] Uma aba toca por vez (`AppModel`); `.inactive` (Central de Controle) nao dispara mais nada.
- [x] Fila: resolucao pelo `videoID`, nova tentativa quando a URL expira, tarefas canceladas no reset.

### Fase 1.5 — Player nativo (`AVPlayer`)
- [x] Quando a pagina comeca a tocar (app em primeiro plano), o conteudo passa para o `NativePlayer` via manifesto HLS do YouTubeKit.
- [x] Video: painel nativo no topo da aba YouTube, PiP manual e automatico ao sair do app.
- [x] Musica: mini player, fila da playlist, segundo plano e tela bloqueada.
- [x] KSPlayer e FFmpegKit removidos.
- [x] YouTube Music: ID/titulo/artista/tempo lidos do player da pagina (`getVideoData()`), nao da URL.
- [x] Validado no iPhone: video com PiP e segundo plano, musica clicada tocando no player nativo, tela bloqueada, ligacoes/fone e convivencia com outros apps.

### Fase 2 — Arquitetura
- [x] `BrowserViewModel` dividido: `WebMediaBridge` (scripts + eventos da página), `PlaybackController` (fila, resolução, tela bloqueada, sessão) e o próprio ViewModel só com navegação e a passagem página -> player.
- [x] Scripts JS em `YouTubePiP/Scripts/*.js`; `MutationObserver` com debounce (`requestAnimationFrame`).
- [x] Tipos renomeados: `MediaTrack`, `PageMediaSnapshot`, `YouTubeStreamResolver`.
- [x] Pacote local `YouTubePiPCore` com a lógica pura e 19 testes (`swift test`), com fixtures reais.
- [x] Corrigido: a fila do YouTube Music vinha sem IDs (o link sumiu do DOM); agora lê `item.data`.
- [x] Política de links: externos no Safari, `youtube://` ignorado, login do Google dentro do app.
- [x] Projeto com pasta sincronizada (sem editar o `.xcodeproj` a cada arquivo); entitlement de Keychain removido.
- [x] Textos com acento, `developmentRegion = pt-BR` e `Localizable.xcstrings` (o Xcode preenche as chaves ao abrir o projeto).

## Proximas fases

### Fase 3 — Experiencia de uso
- [ ] Mensagens de status que somem sozinhas; indicador de carregamento (`isLoading`).
- [ ] Barra inferior sem cobrir a navegacao do site (`safeAreaInset`).
- [ ] Mini player do Music com capa, barra de tempo e fila visivel/editavel.
- [ ] Diagnostico de midia escondido atras de uma opcao de depuracao.

### Fase 4 — Funcionalidades
- [ ] Timer para dormir (15/30/60 min ou fim da faixa).
- [ ] Botao de AirPlay (`AVRoutePickerView`).
- [ ] Velocidade de reproducao e qualidade (limite de bitrate, economia de dados).
- [ ] Extensao de compartilhamento / esquema de URL para abrir links do YouTube no app.
- [ ] Historico e "continuar de onde parou".
- [ ] Modo somente audio tambem na aba YouTube (podcasts, videos longos).

### Fase 5 — Interface nativa via API (YouTubeKit)
Objetivo: trocar a WebView por telas nativas, mais rapidas e fluidas, aos poucos, mantendo a WebView como reserva.

- [ ] Busca nativa (videos, musicas, artistas, playlists) abrindo direto no `NativePlayer`.
- [ ] YouTube Music nativo: fila, biblioteca e playlists.
- [ ] Login: entrar uma vez numa WebView e reaproveitar os cookies da conta nas chamadas da API (biblioteca, inscricoes, historico, "Gostei").
- [ ] Tela inicial e paginas de canal/artista nativas.
- [ ] WebView como reserva para o que ainda nao for nativo.

Riscos: e a API interna do YouTube (nao a oficial), entao mudancas do YouTube podem quebrar telas ate o YouTubeKit ser atualizado. E bem mais trabalho que as outras fases, porque a interface inteira e refeita.

## Observacao
Reproducao em segundo plano e uso dos streams fora do player oficial violam os Termos do YouTube: serve para uso pessoal, nao para a App Store.
