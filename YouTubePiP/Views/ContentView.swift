import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appModel = AppModel()

    var body: some View {
        TabView(selection: $appModel.selectedService) {
            ForEach(MediaService.allCases) { service in
                BrowserView(viewModel: appModel.viewModel(for: service))
                    .tabItem {
                        Label(service.displayName, systemImage: service.tabIcon)
                    }
                    .tag(service)
            }
        }
        .environmentObject(appModel.settings)
        .environmentObject(appModel.history)
        .onChange(of: scenePhase) { newPhase in
            appModel.handleScenePhase(newPhase)
        }
        // ytpip://open?url=<link> ou ytpip://watch?v=<id>
        .onOpenURL { url in
            LinkRouter.shared.open(url)
        }
    }
}
