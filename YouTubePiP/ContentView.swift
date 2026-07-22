import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedService: MediaService = .youtube
    @StateObject private var youtubeViewModel = BrowserViewModel(service: .youtube)
    @StateObject private var youtubeMusicViewModel = BrowserViewModel(service: .youtubeMusic)

    var body: some View {
        TabView(selection: $selectedService) {
            BrowserView(viewModel: youtubeViewModel)
                .tabItem {
                    Label(MediaService.youtube.rawValue, systemImage: MediaService.youtube.tabIcon)
                }
                .tag(MediaService.youtube)

            BrowserView(viewModel: youtubeMusicViewModel)
                .tabItem {
                    Label(MediaService.youtubeMusic.rawValue, systemImage: MediaService.youtubeMusic.tabIcon)
                }
                .tag(MediaService.youtubeMusic)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .inactive || newPhase == .background {
                selectedViewModel.prepareForBackgroundPlayback()
            }
        }
    }

    private var selectedViewModel: BrowserViewModel {
        switch selectedService {
        case .youtube:
            return youtubeViewModel
        case .youtubeMusic:
            return youtubeMusicViewModel
        }
    }
}
