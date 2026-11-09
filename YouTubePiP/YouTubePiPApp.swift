import SwiftUI

@main
struct YouTubePiPApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Apenas a categoria: a sessao e ativada quando algo realmente toca,
        // para nao interromper o audio de outros apps ao abrir o app.
        AudioSessionManager.shared.configureCategory()
        return true
    }
}
