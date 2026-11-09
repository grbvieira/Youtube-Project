# YouTube PiP

App iOS em SwiftUI que abre o YouTube e o YouTube Music em abas separadas, cada uma usando sua propria `WKWebView`.

## Recursos configurados

- Aba YouTube carregando `https://www.youtube.com`.
- Aba YouTube Music carregando `https://music.youtube.com`.
- Navegacao independente em cada aba, com login (cookies) compartilhado entre elas.
- Apenas uma aba toca por vez: ao iniciar a reproducao em uma, a outra e pausada.
- YouTube Music em modo somente audio, com o video oculto para manter apenas a reproducao sonora.
- Navegacao basica: voltar, avancar, inicio e recarregar.
- Ao dar play na pagina, o conteudo passa para o player nativo (`AVPlayer`): video em painel no topo da aba YouTube, com PiP manual e automatico ao sair do app; musica em mini player na aba YouTube Music, com fila e controles na tela bloqueada.
- Midia inline habilitada.
- Picture in Picture habilitado na configuracao da WebView.
- Script injetado para preparar os elementos `<video>` do YouTube para PiP.
- Sessao de audio na categoria `.playback`, ativada so quando o player nativo toca (nao interrompe outros apps ao abrir), com tratamento de interrupcoes (ligacoes) e pausa ao desconectar o fone.
- Background mode `audio` no `Info.plist`, que cobre audio, AirPlay e Picture in Picture no iOS.
- Keychain Sharing habilitado via `YouTubePiP.entitlements` para o grupo do proprio app.

## Arquitetura

- `ContentView.swift`: composicao das abas.
- `AppModel.swift`: dono dos dois navegadores; coordena a reproducao entre abas e o ciclo de vida da cena.
- `AudioSessionManager.swift`: categoria/ativacao da `AVAudioSession`, interrupcoes e mudancas de rota.
- `BrowserView.swift`: interface do navegador, status e comandos de usuario.
- `BrowserViewModel.swift`: estado de navegacao, passagem da pagina para o player nativo, fila e scripts de midia.
- `NativePlayer.swift`: `AVPlayer` + `AVPictureInPictureController` (segundo plano e PiP).
- `YouTubeWebView.swift`: ponte `UIViewRepresentable` entre SwiftUI e `WKWebView`.
- `MediaService.swift`: configuracoes especificas do YouTube e YouTube Music.

## Roadmap

Veja [ROADMAP.md](ROADMAP.md) para o que ja foi feito e as proximas fases.

## Como rodar

Abra o projeto no Xcode:

```sh
open YouTubePiP.xcodeproj
```

Selecione o target `YouTubePiP`, escolha um simulador ou iPhone real e rode.

## Observacao importante

O app habilita as capacidades de PiP e reproducao em segundo plano que o iOS permite para uma WebView. Ainda assim, o comportamento final do video do YouTube depende do proprio YouTube, do player web carregado, do tipo de conta/conteudo e das politicas do iOS. Ou seja: o app configura o suporte, mas nao consegue forcar o YouTube a liberar PiP/background playback quando o site bloquear esse fluxo.

O Keychain Sharing adicionado e uma permissao do app para o proprio chaveiro. Ele nao concede acesso direto a senhas, passkeys ou chaves de acesso do dominio `google.com`; essas credenciais continuam controladas pelo iOS/Safari/Google e so aparecem quando a plataforma e o site permitem.
