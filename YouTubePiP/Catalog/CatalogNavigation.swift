import SwiftUI
import YouTubePiPCore

/// Acoes que as telas nativas pedem para a aba (tocar, abrir na pagina).
struct CatalogActions {
    let playVideo: (MediaTrack) -> Void
    let playTracks: ([MediaTrack], Int) -> Void
    let openChannelPage: (String) -> Void
}

extension View {
    /// Destinos comuns das telas nativas: playlists e canais.
    /// `onLeave` fecha a tela atual (sheet) antes de tocar, quando for o caso.
    func catalogDestinations(_ actions: CatalogActions, onLeave: @escaping () -> Void = {}) -> some View {
        navigationDestination(for: CatalogPlaylist.self) { playlist in
            PlaylistDetailView(playlist: playlist) { tracks, index in
                onLeave()
                actions.playTracks(tracks, index)
            }
        }
        .navigationDestination(for: CatalogChannel.self) { channel in
            ChannelView(channel: channel, actions: actions, onLeave: onLeave)
        }
    }
}
