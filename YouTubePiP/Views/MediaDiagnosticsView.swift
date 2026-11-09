import SwiftUI
import UIKit

/// Mostra o JSON capturado da pagina (para depurar a passagem para o player nativo).
struct MediaDiagnosticsView: View {
    let report: String
    let canStartNativePlayback: Bool
    let onStartNativePlayback: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button(action: onStartNativePlayback) {
                        Label("Tocar no player nativo", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStartNativePlayback)

                    if !canStartNativePlayback {
                        Text("Nenhuma música em reprodução foi identificada neste diagnóstico.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Text(report)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Diagnóstico de mídia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = report
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copiar diagnóstico")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
