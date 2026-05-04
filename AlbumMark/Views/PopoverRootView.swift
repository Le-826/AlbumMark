import MusicKit
import SwiftUI
import AppKit

struct PopoverRootView: View {
    @EnvironmentObject private var observer: MusicPlayerObserver
    @EnvironmentObject private var store: AlbumProgressStore
    @EnvironmentObject private var settings: AppSettings
    @State private var showingSettings = false

    private var unfinishedAlbums: [AlbumProgressRecord] {
        store.visibleRecords(hideCompletedThreshold: settings.hideCompletedThreshold)
            .filter { !matchesNowPlayingAlbum($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                header
                if showingSettings {
                    SettingsView(showsHeader: false)
                } else {
                    actionMessage
                    NowPlayingView()
                    unfinishedSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(width: 380, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(showingSettings ? "Settings" : "AlbumMark")
                .font(.system(size: 16, weight: .semibold))
            Spacer()

            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: showingSettings ? "chevron.left" : "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(showingSettings ? "Back" : "Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit AlbumMark")
        }
    }

    @ViewBuilder
    private var actionMessage: some View {
        if let message = observer.actionMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: message.hasPrefix("Could not") ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(message.hasPrefix("Could not") ? .orange : .green)
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var unfinishedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Continue Albums", systemImage: "books.vertical")

            if unfinishedAlbums.isEmpty {
                EmptyStateView(
                    systemImage: "",
                    title: "No saved album progress yet",
                    message: nil
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(unfinishedAlbums) { record in
                        AlbumProgressCardView(record: record)
                    }
                }
            }
        }
    }

    private func matchesNowPlayingAlbum(_ record: AlbumProgressRecord) -> Bool {
        guard let nowPlaying = observer.nowPlaying else { return false }

        if record.albumIdentifier == nowPlaying.albumIdentifier {
            return true
        }

        return normalized(record.albumTitle) == normalized(nowPlaying.albumTitle)
            && normalized(record.artistName) == normalized(nowPlaying.artistName)
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
