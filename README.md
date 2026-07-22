# YouTube PiP

App iOS em SwiftUI que abre o YouTube em uma `WKWebView` na tela inicial.

## Recursos configurados

- `WKWebView` carregando `https://www.youtube.com`.
- Navegacao basica: voltar, avancar, inicio e recarregar.
- Botao de Picture in Picture no toolbar.
- Midia inline habilitada.
- Picture in Picture habilitado na configuracao da WebView.
- Script injetado para preparar os elementos `<video>` do YouTube para PiP.
- Sessao de audio configurada como `.playback`.
- Background mode `audio` no `Info.plist`, que cobre audio, AirPlay e Picture in Picture no iOS.
- Keychain Sharing habilitado via `YouTubePiP.entitlements` para o grupo do proprio app.

## Como rodar

Abra o projeto no Xcode:

```sh
open YouTubePiP.xcodeproj
```

Selecione o target `YouTubePiP`, escolha um simulador ou iPhone real e rode.

## Observacao importante

O app habilita as capacidades de PiP e reproducao em segundo plano que o iOS permite para uma WebView. Ainda assim, o comportamento final do video do YouTube depende do proprio YouTube, do player web carregado, do tipo de conta/conteudo e das politicas do iOS. Ou seja: o app configura o suporte, mas nao consegue forcar o YouTube a liberar PiP/background playback quando o site bloquear esse fluxo.

O Keychain Sharing adicionado e uma permissao do app para o proprio chaveiro. Ele nao concede acesso direto a senhas, passkeys ou chaves de acesso do dominio `google.com`; essas credenciais continuam controladas pelo iOS/Safari/Google e so aparecem quando a plataforma e o site permitem.
