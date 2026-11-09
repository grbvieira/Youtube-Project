import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedService: MediaService = .youtube
    @StateObject private var appModel = AppModel()

    var body: some View {
        TabView(selection: $selectedService) {
            ForEach(MediaService.allCases) { service in
                BrowserView(viewModel: appModel.viewModel(for: service))
                    .tabItem {
                        Label(service.displayName, systemImage: service.tabIcon)
                    }
                    .tag(service)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            appModel.handleScenePhase(newPhase)
        }
    }
}
