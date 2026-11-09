# YouTube PiP

App iOS em SwiftUI que abre o YouTube e o YouTube Music em abas separadas, cada uma com sua própria `WKWebView`. Ao dar play na página, o conteúdo passa para o player nativo do iOS (`AVPlayer`), que continua em segundo plano e em Picture in Picture.

## Recursos

- Abas YouTube (`https://www.youtube.com`) e YouTube Music (`https://music.youtube.com`), com navegação independente e login (cookies) compartilhado.
- Ao dar play na página, o app pausa a página e toca no player nativo:
  - **YouTube:** vídeo num painel no topo da aba, com PiP manual e automático ao sair do app.
  - **YouTube Music:** só áudio, num mini player, com a fila da página/playlist.
- Controles na tela bloqueada e na Central de Controle (play/pausa, próxima, anterior, barra de tempo).
- Apenas uma aba toca por vez.
- Sessão de áudio `.playback` ativada só quando o player nativo toca (não interrompe outros apps ao abrir), com tratamento de interrupções (ligações) e pausa ao desconectar o fone.
- Links externos abrem no Safari; o login do Google fica dentro do app.
- Se o player nativo não conseguir abrir um vídeo, a página volta a tocar (sem segundo plano).

## Arquitetura

```
YouTubePiP/
  App/        YouTubePiPApp, AppModel (coordena as abas e o ciclo de vida),
              BrowserViewModel (navegação + passagem página -> player), MediaService
  Playback/   PlaybackController (fila, resolução, tela bloqueada, interrupções),
              NativePlayer (AVPlayer + PiP), NowPlayingController, AudioSessionManager,
              YouTubeStreamResolver (YouTubeKit -> manifesto HLS)
  Web/        YouTubeWebView (WKWebView, política de links), WebMediaBridge (scripts e eventos da página)
  Scripts/    *.js injetados/avaliados na página
  Views/      ContentView, BrowserView, PlayerViews (painel de vídeo, mini player), MediaDiagnosticsView
Packages/YouTubePiPCore/
              Lógica pura e testável: MediaTrack, PageMediaParser, PlaybackQueue, LinkPolicy
```

A pasta `YouTubePiP/` é sincronizada com o projeto: arquivos novos entram no build sem editar o `.xcodeproj`.

## Como rodar

```sh
open YouTubePiP.xcodeproj
```

Selecione o target `YouTubePiP`, escolha um iPhone e rode.

## Testes

A lógica pura roda no Mac, sem simulador:

```sh
cd Packages/YouTubePiPCore && swift test
```

Os fixtures em `Tests/YouTubePiPCoreTests/Fixtures` são capturas reais do `media-diagnostics.js`.

## Roadmap

Veja [ROADMAP.md](ROADMAP.md).

## Observação

O player nativo usa os streams obtidos pelo YouTubeKit (API interna do YouTube); mudanças do YouTube podem exigir atualizar o pacote. Reprodução em segundo plano fora do player oficial viola os Termos do YouTube: serve para uso pessoal, não para a App Store.
