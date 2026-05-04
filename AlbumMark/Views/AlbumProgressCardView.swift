import SwiftUI

struct AlbumProgressCardView: View {
    @EnvironmentObject private var observer: MusicPlayerObserver
    @EnvironmentObject private var store: AlbumProgressStore

    let record: AlbumProgressRecord
    private let artworkSize: CGFloat = 76

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ArtworkView(url: record.artworkURL, size: artworkSize)
                .frame(width: artworkSize, height: artworkSize)

            VStack(alignment: .leading, spacing: 3) {
                titleBlock

                ThinProgressBar(value: record.progressFraction)
                    .padding(.top, 2)
            }
            .frame(minHeight: artworkSize, alignment: .center)

            Spacer(minLength: 4)

            controls
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(record.albumTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(record.artistName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.72))
                .lineLimit(1)

            Text(record.currentTrackTitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(progressStatus)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var controls: some View {
        HStack(spacing: 7) {
            Button {
                observer.resume(record)
            } label: {
                Text("▶")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Resume album")
            .accessibilityLabel("Resume album")

            Button(role: .destructive) {
                store.remove(record)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Remove saved progress")
            .accessibilityLabel("Remove saved progress")
            .foregroundStyle(.secondary)
        }
        .padding(.top, 1)
    }

    private var progressStatus: String {
        "\(record.trackStatus) · \(Int((record.progressFraction * 100).rounded()))%"
    }
}
