import SwiftUI

/// Curtir o video e se inscrever no canal, para quem esta logado.
struct AccountActionsView: View {
    let videoID: String?

    @EnvironmentObject private var account: AccountSession
    @State private var state: VideoAccountState?
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        if account.isSignedIn, let videoID {
            HStack(spacing: 16) {
                Button(action: toggleLike) {
                    Image(systemName: state?.isLiked == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                }
                .disabled(state == nil || isUpdating)
                .accessibilityLabel(state?.isLiked == true ? "Remover gostei" : "Gostei")

                if let subscribed = state?.isSubscribed, state?.channelID != nil {
                    Button(action: toggleSubscription) {
                        Image(systemName: subscribed ? "bell.fill" : "person.badge.plus")
                    }
                    .disabled(isUpdating)
                    .accessibilityLabel(subscribed ? "Cancelar inscrição" : "Inscrever-se")
                }
            }
            .task(id: videoID) { await load(videoID) }
            .alert("Não foi possível atualizar", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func load(_ videoID: String) async {
        state = nil
        state = try? await YouTubeCatalog.shared.accountState(for: videoID)
    }

    /// Atualiza na hora e desfaz se o YouTube recusar.
    private func toggleLike() {
        guard let current = state else { return }
        let liked = !current.isLiked
        state?.isLiked = liked
        update(revert: { state?.isLiked = current.isLiked }) {
            try await YouTubeCatalog.shared.setLiked(liked, videoID: current.videoID)
        }
    }

    private func toggleSubscription() {
        guard let current = state, let channelID = current.channelID, let subscribed = current.isSubscribed else { return }
        state?.isSubscribed = !subscribed
        update(revert: { state?.isSubscribed = subscribed }) {
            try await YouTubeCatalog.shared.setSubscribed(!subscribed, channelID: channelID)
        }
    }

    private func update(revert: @escaping () -> Void, _ operation: @escaping () async throws -> Void) {
        isUpdating = true
        Task {
            defer { isUpdating = false }
            do {
                try await operation()
            } catch {
                revert()
                errorMessage = error.localizedDescription
            }
        }
    }
}
