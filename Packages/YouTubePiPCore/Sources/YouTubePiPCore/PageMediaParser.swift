import Foundation

/// Converte o JSON gerado por `media-diagnostics.js` em um `PageMediaSnapshot`.
public enum PageMediaParser {
    /// Parametros que so valem para uma requisicao especifica de um trecho do stream.
    static let requestOnlyParameters: Set<String> = ["range", "rn", "rbuf", "alr", "ump", "srfvp"]

    public static func snapshot(fromJSON data: Data) -> PageMediaSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return snapshot(from: object)
    }

    public static func snapshot(from object: Any) -> PageMediaSnapshot? {
        guard let report = object as? [String: Any] else { return nil }

        let activeElement = report["activeElement"] as? [String: Any]
        let metadata = report["metadata"] as? [String: Any] ?? [:]
        let pageComponents = (report["pageURL"] as? String)
            .flatMap(URL.init(string:))
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }

        guard let videoID = (metadata["videoID"] as? String).nonEmpty
            ?? pageComponents?.queryItems?.first(where: { $0.name == "v" })?.value.nonEmpty
        else { return nil }

        let playlistID = (metadata["playlistID"] as? String).nonEmpty
            ?? pageComponents?.queryItems?.first(where: { $0.name == "list" })?.value.nonEmpty
        // O tempo do player da pagina e mais confiavel que o do elemento <video> (anuncios, troca de faixa).
        let currentTime = number(metadata["currentTime"]) ?? number(activeElement?["currentTime"]) ?? 0

        let currentTrack = MediaTrack(
            videoID: videoID,
            title: (metadata["title"] as? String).nonEmpty ?? "",
            artist: (metadata["artist"] as? String).nonEmpty ?? "",
            artworkURL: webURL(metadata["artworkURL"]),
            duration: number(activeElement?["duration"])
        )

        return PageMediaSnapshot(
            currentTrack: currentTrack,
            fallbackStreamURL: latestAudioStreamURL(in: report["resourceURLs"] as? [String] ?? []),
            currentTime: max(0, currentTime),
            playlistID: playlistID,
            queue: queue(from: report["queueItems"])
        )
    }

    /// A URL de audio mais recente vista nos recursos da pagina, sem os parametros de trecho.
    public static func latestAudioStreamURL(in resourceURLs: [String]) -> URL? {
        for value in resourceURLs.reversed() {
            guard
                var components = URLComponents(string: value),
                components.host?.hasSuffix("googlevideo.com") == true,
                components.path.contains("videoplayback")
            else { continue }

            let queryItems = components.queryItems ?? []
            let mimeType = queryItems.first(where: { $0.name == "mime" })?.value ?? ""
            guard mimeType.lowercased().hasPrefix("audio/") else { continue }

            components.queryItems = queryItems.filter { !requestOnlyParameters.contains($0.name) }
            if let url = components.url {
                return url
            }
        }
        return nil
    }

    static func queue(from object: Any?) -> [MediaTrack] {
        guard let items = object as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let videoID = (item["videoID"] as? String).nonEmpty else { return nil }
            return MediaTrack(
                videoID: videoID,
                title: (item["title"] as? String).nonEmpty ?? "",
                artist: (item["artist"] as? String).nonEmpty ?? "",
                artworkURL: webURL(item["artworkURL"]),
                duration: number(item["duration"])
            )
        }
    }

    /// Apenas URLs http(s): imagens ainda nao carregadas aparecem como `data:` (GIF de 1 pixel).
    private static func webURL(_ value: Any?) -> URL? {
        guard let url = (value as? String).nonEmpty.flatMap(URL.init(string:)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    private static func number(_ value: Any?) -> Double? {
        // Booleanos do JSON tambem chegam como NSNumber; nao sao tempos validos.
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }
}

extension Optional where Wrapped == String {
    /// O texto sem espacos nas pontas, ou `nil` se ficar vazio.
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
