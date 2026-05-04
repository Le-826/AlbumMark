import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let observer: MusicPlayerObserver
    private let store: AlbumProgressStore
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    init(observer: MusicPlayerObserver, store: AlbumProgressStore, settings: AppSettings) {
        self.observer = observer
        self.store = store
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()

        configureStatusItem()
        configurePopover()
        bindStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "AlbumMark")
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.toolTip = "AlbumMark"
    }

    private func configurePopover() {
        let rootView = PopoverRootView()
            .environmentObject(observer)
            .environmentObject(store)
            .environmentObject(settings)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 390, height: 620)
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    private func bindStatusItem() {
        observer.$progress
            .combineLatest(observer.$nowPlaying)
            .receive(on: RunLoop.main)
            .sink { [weak self] progress, nowPlaying in
                self?.updateStatusItem(progress: progress, nowPlaying: nowPlaying)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(progress: AlbumProgressResult?, nowPlaying: NowPlayingSnapshot?) {
        guard let button = statusItem.button else { return }

        if let progress, nowPlaying?.albumContextIsReliable == true {
            button.title = ""
            button.contentTintColor = nil
            button.toolTip = "\(nowPlaying?.albumTitle ?? "Album") · \(progress.percentageText)"
        } else {
            button.title = ""
            button.contentTintColor = nil
            button.toolTip = "AlbumMark"
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
