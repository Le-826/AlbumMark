import MusicKit
import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var observer: MusicPlayerObserver
    private let artworkSize: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Now Playing", systemImage: "waveform")

            switch observer.authorizationStatus {
            case .authorized:
                authorizedContent
            case .notDetermined:
                authorizationPrompt
            case .denied, .restricted:
                deniedPrompt
            @unknown default:
                authorizationPrompt
            }
        }
    }

    @ViewBuilder
    private var authorizedContent: some View {
        if let snapshot = observer.nowPlaying, let progress = observer.progress {
            HStack(alignment: .center, spacing: 10) {
                ArtworkView(url: snapshot.artworkURL, size: artworkSize)
                    .frame(width: artworkSize, height: artworkSize)

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.albumTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(snapshot.artistName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.72))
                        .lineLimit(1)

                    Text(snapshot.songTitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(progress.statusLine)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    ThinProgressBar(value: progress.percentage)
                        .padding(.top, 2)
                }
                .frame(minHeight: artworkSize, alignment: .center)

                Spacer(minLength: 4)

                Color.clear
                    .frame(width: 47, height: 20)
            }
            .padding(9)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
        } else {
            EmptyStateView(
                systemImage: "",
                title: "No album playing",
                message: observer.statusMessage
            )
        }
    }

    private var authorizationPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            EmptyStateView(
                systemImage: "music.quarternote.3",
                title: "AlbumMark needs Apple Music access to track album progress.",
                message: nil
            )

            Button {
                observer.requestAuthorization()
            } label: {
                Label("Grant Music Access", systemImage: "lock.open")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var deniedPrompt: some View {
        EmptyStateView(
            systemImage: "lock.slash",
            title: "Apple Music access is not available.",
            message: "Enable Media & Apple Music access in System Settings to track album progress."
        )
    }
}
