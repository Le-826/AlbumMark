import AppKit
import SwiftUI

@main
struct AlbumMarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings?
    private var store: AlbumProgressStore?
    private var observer: MusicPlayerObserver?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = AppSettings()
        let store = AlbumProgressStore()
        let observer = MusicPlayerObserver(store: store, settings: settings)
        let menuBarController = MenuBarController(
            observer: observer,
            store: store,
            settings: settings
        )

        self.settings = settings
        self.store = store
        self.observer = observer
        self.menuBarController = menuBarController

        observer.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.saveImmediately()
    }
}
