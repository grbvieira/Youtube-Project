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

### Fase 3 — Experiência de uso
- [x] Avisos passageiros que somem em 4 s (ou com um toque); erros de carregamento continuam com "Tentar novamente".
- [x] Barra de progresso do carregamento da página; "preparando" vira indicador no player, não mensagem.
- [x] Barra inferior fora da página (não cobre mais a navegação do site), com menu "Mais opções".
- [x] Mini player do Music com capa e barra de tempo; toque abre "Tocando agora" com capa grande, controles e fila (tocar, reordenar, remover).
- [x] "Inspecionar mídia" só aparece com "Ferramentas de depuração" ligado no menu.
- [x] Edição da fila no `YouTubePiPCore` com testes (22 no total).

### Fase 4 — Funcionalidades
- [x] Timer para dormir (15/30/45/60 min ou fim da faixa), com aviso do tempo restante.
- [x] Botão de AirPlay (`AVRoutePickerView`) no painel de vídeo e em "Tocando agora".
- [x] Velocidade de reprodução (0,5× a 2×, com o pitch preservado), também na tela bloqueada.
- [x] Qualidade: Automática, Economia de dados (480p) ou Mínima (360p), aplicada ao vivo.
- [x] Modo "Só áudio no YouTube" (podcasts, vídeos longos), trocando sem recarregar.
- [x] Histórico salvo em disco e "continuar de onde parou" (vídeos; no Music, só faixas longas).
- [x] Abrir links: esquema `ytpip://open?url=...`, atalho "Abrir no YouTube PiP" (App Intent, usável na folha de compartilhar via Atalhos) e "Abrir link copiado".
- Nota: uma extensão de compartilhamento própria não foi feita porque o iOS não permite que ela abra o app principal; o atalho cobre o mesmo uso.
- [x] Regras de links, histórico, timer e qualidade no `YouTubePiPCore` (35 testes no total).

## Proximas fases

### Fase 5 — Interface nativa via API (YouTubeKit)
Objetivo: trocar a WebView por telas nativas, mais rápidas e fluidas, aos poucos, mantendo a WebView como reserva.

Testado no Mac antes de começar: busca, sugestões, paginação e playlists funcionam sem login; com os cookies da conta, o YouTubeKit também oferece biblioteca, playlists, inscrições, feed, histórico, curtir e se inscrever.

#### Etapa 5.1 — Busca nativa
- [x] Botão "Buscar" nas duas abas: sugestões enquanto digita, buscas recentes (sem repetir, ignorando acentos) e rolagem infinita.
- [x] Vídeos tocam direto no player nativo; no Music, em áudio, com fila de recomendados.
- [x] Playlists nativas com "Tocar tudo", "Aleatório" e tocar a partir de um item.
- [x] Canais abrem na página (tela nativa fica para a 5.3).
- [x] Se o player nativo falhar num vídeo vindo da busca, a página abre esse vídeo.
- [x] Validado no iPhone.

#### Etapa 5.2 — Conta (login reaproveitado)
- [x] Login lido dos cookies `youtube.com` da WebView (só na memória, só enviados ao YouTube); regra com testes no `YouTubePiPCore`.
- [x] Botão "Biblioteca" (com a foto da conta) e "Entrar no YouTube" abrindo o login do Google na página.
- [x] Biblioteca nativa: "Gostei", "Assistir mais tarde", suas playlists, novidades das inscrições e canais inscritos.
- [x] Curtir e se inscrever pelo player (atualiza na hora e desfaz se o YouTube recusar).
- [x] Validado no iPhone com a conta.

#### Etapa 5.3 — Telas de navegação
- [ ] Tela inicial e "Em alta" nativas.
- [ ] Páginas de canal/artista nativas.
- [ ] WebView como reserva para o que ainda não for nativo.

Riscos: é a API interna do YouTube (não a oficial), então mudanças do YouTube podem quebrar telas até o YouTubeKit ser atualizado. A busca do YouTubeKit não tem filtro por tipo: os resultados são principalmente vídeos.

## Observacao
Reproducao em segundo plano e uso dos streams fora do player oficial violam os Termos do YouTube: serve para uso pessoal, nao para a App Store.
