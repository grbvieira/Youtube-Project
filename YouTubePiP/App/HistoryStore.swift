import Foundation
import YouTubePiPCore

/// Historico de reproducao salvo em disco (Application Support/history.json).
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var history: PlaybackHistory

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL = HistoryStore.defaultFileURL) {
        self.fileURL = fileURL
        history = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode(PlaybackHistory.self, from: $0) }
            ?? PlaybackHistory()
    }

    var entries: [HistoryEntry] { history.entries }

    func resumePosition(for videoID: String) -> TimeInterval? {
        history.resumePosition(for: videoID)
    }

    func record(_ track: MediaTrack, position: TimeInterval, duration: TimeInterval?, isMusic: Bool) {
        history.record(track, position: position, duration: duration, isMusic: isMusic, at: Date())
        scheduleSave()
    }

    func remove(videoID: String) {
        history.remove(videoID: videoID)
        scheduleSave()
    }

    func clear() {
        history.clear()
        scheduleSave()
    }

    /// Agrupa gravacoes seguidas (a posicao e atualizada a cada poucos segundos).
    private func scheduleSave() {
        saveTask?.cancel()
        let history = history
        let fileURL = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(history) else { return }
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("history.json")
    }
}
