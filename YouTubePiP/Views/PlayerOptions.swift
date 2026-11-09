import AVKit
import SwiftUI
import YouTubePiPCore

/// Botao do sistema para escolher a saida (AirPlay, Bluetooth, alto-falante).
struct RoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .label
        picker.activeTintColor = .tintColor
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Velocidade e timer para dormir.
struct PlayerOptionsMenu: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { playback.rate }, set: { playback.setRate($0) })) {
                ForEach(PlaybackRate.options, id: \.self) { rate in
                    Text(rateTitle(rate)).tag(rate)
                }
            } label: {
                Label("Velocidade: \(rateTitle(playback.rate))", systemImage: "speedometer")
            }
            .pickerStyle(.menu)

            Picker(selection: Binding(get: { selectedSleepOption }, set: { playback.setSleepTimer($0) })) {
                Text("Desligado").tag(SleepTimer.Option?.none)
                ForEach(SleepTimer.presets, id: \.self) { option in
                    Text(sleepTitle(option)).tag(Optional(option))
                }
            } label: {
                Label(sleepMenuTitle, systemImage: "moon.zzz")
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: playback.sleepTimer.isActive ? "moon.zzz.fill" : "slider.horizontal.3")
        }
        .accessibilityLabel("Opções do player")
    }

    /// O timer em andamento nao corresponde mais a um preset exato; mostra so se esta ligado.
    private var selectedSleepOption: SleepTimer.Option? {
        if playback.sleepTimer.stopsAtEndOfTrack { return .endOfTrack }
        return nil
    }

    private var sleepMenuTitle: String {
        if playback.sleepTimer.stopsAtEndOfTrack {
            return String(localized: "Timer: fim da faixa")
        }
        if let remaining = playback.sleepRemaining {
            return String(localized: "Timer: \(formatTime(remaining))")
        }
        return String(localized: "Timer para dormir")
    }

    private func sleepTitle(_ option: SleepTimer.Option) -> String {
        switch option {
        case .minutes(let minutes): String(localized: "\(minutes) minutos")
        case .endOfTrack: String(localized: "Fim da faixa")
        }
    }
}

/// Mostra o tempo restante do timer para dormir, quando ligado.
struct SleepTimerBadge: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        if playback.sleepTimer.isActive {
            Label(
                playback.sleepTimer.stopsAtEndOfTrack
                    ? String(localized: "Pausa no fim da faixa")
                    : String(localized: "Pausa em \(formatTime(playback.sleepRemaining ?? 0))"),
                systemImage: "moon.zzz.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

func rateTitle(_ rate: Float) -> String {
    rate == 1 ? String(localized: "Normal") : rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
}
