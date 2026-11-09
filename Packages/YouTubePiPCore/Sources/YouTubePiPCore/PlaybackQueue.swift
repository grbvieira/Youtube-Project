import Foundation

/// Fila de reproducao do player nativo. Regras puras (sem rede nem player), para poderem ser testadas.
public struct PlaybackQueue: Equatable, Sendable {
    public private(set) var tracks: [MediaTrack]
    public private(set) var currentIndex: Int

    public init(tracks: [MediaTrack] = [], currentIndex: Int = 0) {
        self.tracks = tracks
        self.currentIndex = tracks.indices.contains(currentIndex) ? currentIndex : 0
    }

    /// Monta a fila a partir do que a pagina estava tocando.
    /// - Parameter includePageQueue: no YouTube Music usa a fila exibida na pagina;
    ///   no YouTube toca apenas o video aberto.
    public init(snapshot: PageMediaSnapshot, includePageQueue: Bool) {
        var seenIDs = Set<String>()
        var tracks = (includePageQueue ? snapshot.queue : []).filter { seenIDs.insert($0.videoID).inserted }
        let current = snapshot.currentTrack

        if let index = tracks.firstIndex(where: { $0.videoID == current.videoID }) {
            tracks[index] = current.mergingMetadata(from: tracks[index])
            self.init(tracks: tracks, currentIndex: index)
        } else {
            tracks.insert(current, at: 0)
            self.init(tracks: tracks, currentIndex: 0)
        }
    }

    public var isEmpty: Bool { tracks.isEmpty }
    public var current: MediaTrack? { tracks.indices.contains(currentIndex) ? tracks[currentIndex] : nil }
    public var hasNext: Bool { currentIndex + 1 < tracks.count }
    public var hasPrevious: Bool { currentIndex > 0 }

    public func contains(index: Int) -> Bool { tracks.indices.contains(index) }

    public subscript(index: Int) -> MediaTrack? {
        tracks.indices.contains(index) ? tracks[index] : nil
    }

    /// Torna `index` a faixa atual. Retorna `false` se o indice nao existir.
    @discardableResult
    public mutating func moveTo(_ index: Int) -> Bool {
        guard tracks.indices.contains(index) else { return false }
        currentIndex = index
        return true
    }

    /// Substitui a faixa em `index` (por exemplo, depois de resolver a URL).
    public mutating func replace(at index: Int, with track: MediaTrack) {
        guard tracks.indices.contains(index), tracks[index].videoID == track.videoID else { return }
        tracks[index] = track
    }

    /// Esquece a URL resolvida (ela expirou) para que seja resolvida de novo.
    public mutating func invalidateStream(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        tracks[index].streamURL = nil
    }

    /// Guarda uma faixa pre-resolvida, localizando-a pelo `videoID` (a fila pode ter sido reordenada).
    /// Nao sobrescreve uma URL ja resolvida.
    public mutating func storePrefetched(_ track: MediaTrack) {
        guard let index = tracks.firstIndex(where: { $0.videoID == track.videoID }),
              tracks[index].streamURL == nil
        else { return }
        tracks[index] = track
    }

    /// Proximas faixas (a partir da seguinte) que ainda nao tem URL.
    public func unresolvedUpcoming(limit: Int) -> [MediaTrack] {
        guard limit > 0, currentIndex + 1 < tracks.count else { return [] }
        let end = min(tracks.count, currentIndex + 1 + limit)
        return tracks[(currentIndex + 1)..<end].filter { $0.streamURL == nil }
    }

    // MARK: - Edicao pelo usuario

    /// Remove uma faixa da fila. A faixa atual nao pode ser removida (retorna `false`).
    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        guard tracks.indices.contains(index), index != currentIndex else { return false }
        tracks.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        }
        return true
    }

    /// Move a faixa em `source` para antes da posicao `destination` (mesma convencao de
    /// `onMove` do SwiftUI: `destination` vai de 0 a `tracks.count`). A faixa atual continua atual.
    public mutating func move(from source: Int, to destination: Int) {
        guard tracks.indices.contains(source), (0...tracks.count).contains(destination) else { return }
        let target = destination > source ? destination - 1 : destination
        guard target != source else { return }

        let track = tracks.remove(at: source)
        tracks.insert(track, at: target)

        if source == currentIndex {
            currentIndex = target
        } else {
            var index = currentIndex
            if source < index { index -= 1 }
            if target <= index { index += 1 }
            currentIndex = index
        }
    }

    /// Substitui a fila pela da playlist, mantendo a faixa atual (e o que ja foi resolvido dela).
    /// Retorna `false` se nada mudou (playlist vazia ou a faixa atual mudou nesse meio tempo).
    @discardableResult
    public mutating func mergePlaylist(_ playlist: [MediaTrack], expectedCurrentVideoID: String) -> Bool {
        guard !playlist.isEmpty, let current, current.videoID == expectedCurrentVideoID else { return false }

        if let index = playlist.firstIndex(where: { $0.videoID == current.videoID }) {
            var merged = playlist
            merged[index] = current.mergingMetadata(from: merged[index])
            tracks = merged
            currentIndex = index
        } else {
            tracks = [current] + playlist.filter { $0.videoID != current.videoID }
            currentIndex = 0
        }
        return true
    }
}
