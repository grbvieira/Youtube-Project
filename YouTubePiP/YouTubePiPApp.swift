import AVFoundation
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
        configurePlaybackSession()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        configurePlaybackSession()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        configurePlaybackSession()
    }

    private func configurePlaybackSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            print("Unable to activate background playback audio session: \(error)")
        }
    }
}
