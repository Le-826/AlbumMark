import Foundation

enum AlbumProgressCalculator {
    static func calculate(for snapshot: NowPlayingSnapshot) -> AlbumProgressResult {
        let trackNumber = snapshot.trackNumber
        let totalTrackCount = snapshot.totalTrackCount
        let playbackPosition = max(snapshot.playbackPosition, 0)

        if let fullDurationResult = calculateWithFullAlbumDurations(
            snapshot: snapshot,
            playbackPosition: playbackPosition
        ) {
            return fullDurationResult
        }

        if let trackNumber,
           let totalTrackCount,
           totalTrackCount > 0,
           trackNumber > 0 {
            let trackProgress: Double
            if let songDuration = snapshot.songDuration, songDuration > 0 {
                trackProgress = min(max(playbackPosition / songDuration, 0), 1)
            } else {
                trackProgress = 0
            }

            let percentage = min(max((Double(trackNumber - 1) + trackProgress) / Double(totalTrackCount), 0), 1)
            return AlbumProgressResult(
                percentage: percentage,
                method: .trackCountAndSongProgress,
                statusLine: statusLine(trackNumber: trackNumber, totalTrackCount: totalTrackCount, percentage: percentage),
                resumeLine: resumeLine(position: playbackPosition, trackNumber: trackNumber, title: snapshot.songTitle),
                totalAlbumDuration: nil
            )
        }

        if let songDuration = snapshot.songDuration, songDuration > 0 {
            let percentage = min(max(playbackPosition / songDuration, 0), 1)
            return AlbumProgressResult(
                percentage: percentage,
                method: .currentTrackOnly,
                statusLine: "\(Int((percentage * 100).rounded()))% of current track",
                resumeLine: resumeLine(position: playbackPosition, trackNumber: trackNumber, title: snapshot.songTitle),
                totalAlbumDuration: nil
            )
        }

        return AlbumProgressResult(
            percentage: 0,
            method: .unavailable,
            statusLine: "Progress unavailable",
            resumeLine: resumeLine(position: playbackPosition, trackNumber: trackNumber, title: snapshot.songTitle),
            totalAlbumDuration: nil
        )
    }

    private static func calculateWithFullAlbumDurations(
        snapshot: NowPlayingSnapshot,
        playbackPosition: TimeInterval
    ) -> AlbumProgressResult? {
        let tracks = snapshot.albumTracks.sorted { left, right in
            switch (left.trackNumber, right.trackNumber) {
            case let (leftNumber?, rightNumber?):
                return leftNumber < rightNumber
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
        }

        guard !tracks.isEmpty else { return nil }
        let durations = tracks.compactMap(\.duration)
        guard durations.count == tracks.count else { return nil }

        let totalDuration = durations.reduce(0, +)
        guard totalDuration > 0 else { return nil }

        guard let currentIndex = tracks.firstIndex(where: { track in
            track.id == snapshot.trackIdentifier || track.trackNumber == snapshot.trackNumber
        }) else {
            return nil
        }

        let previousDuration = tracks[..<currentIndex].compactMap(\.duration).reduce(0, +)
        let currentDuration = tracks[currentIndex].duration ?? snapshot.songDuration ?? 0
        let boundedPosition = min(playbackPosition, max(currentDuration, 0))
        let percentage = min(max((previousDuration + boundedPosition) / totalDuration, 0), 1)
        let displayTrackNumber = tracks[currentIndex].trackNumber ?? snapshot.trackNumber ?? currentIndex + 1
        let totalTrackCount = snapshot.totalTrackCount ?? tracks.count

        return AlbumProgressResult(
            percentage: percentage,
            method: .fullAlbumDurations,
            statusLine: statusLine(trackNumber: displayTrackNumber, totalTrackCount: totalTrackCount, percentage: percentage),
            resumeLine: resumeLine(position: playbackPosition, trackNumber: displayTrackNumber, title: snapshot.songTitle),
            totalAlbumDuration: totalDuration
        )
    }

    static func statusLine(trackNumber: Int?, totalTrackCount: Int?, percentage: Double) -> String {
        let percentageText = "\(Int((percentage * 100).rounded()))% complete"

        if let trackNumber, let totalTrackCount {
            return "Track \(trackNumber) of \(totalTrackCount) · \(percentageText)"
        }

        if let trackNumber {
            return "Track \(trackNumber) · \(percentageText)"
        }

        return percentageText
    }

    static func resumeLine(position: TimeInterval, trackNumber: Int?, title: String) -> String {
        let formattedPosition = TimeFormatter.positionString(from: position)
        if let trackNumber {
            return "Resume from \(formattedPosition) in Track \(trackNumber)"
        }

        return "Resume from \(formattedPosition) in \"\(title)\""
    }
}
