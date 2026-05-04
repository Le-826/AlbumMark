import AppKit
import Foundation

enum TestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@MainActor
struct LogicTestRunner {
    private var failures: [String] = []

    mutating func run() async {
        testTimeFormatter()
        testProgressWithFullAlbumDurations()
        testProgressFallbacks()
        testAlbumProgressRecord()
        await testAlbumProgressStore()
        testResumeScriptDoesNotFallbackToCurrentPlayback()
        testArtworkScriptCompiles()
        finish()
    }

    private mutating func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }

    private mutating func checkClose(_ actual: Double, _ expected: Double, tolerance: Double = 0.0001, _ message: String) {
        if abs(actual - expected) > tolerance {
            failures.append("\(message): expected \(expected), got \(actual)")
        }
    }

    private mutating func testTimeFormatter() {
        check(TimeFormatter.positionString(from: 0) == "0:00", "zero time formats as 0:00")
        check(TimeFormatter.positionString(from: 65) == "1:05", "minute time formats as m:ss")
        check(TimeFormatter.positionString(from: 3_661) == "1:01:01", "hour time formats as h:mm:ss")
        check(TimeFormatter.positionString(from: -12) == "0:00", "negative time clamps to zero")
    }

    private mutating func testProgressWithFullAlbumDurations() {
        let snapshot = makeSnapshot(
            trackIdentifier: "t2",
            trackNumber: 2,
            totalTrackCount: 3,
            playbackPosition: 50,
            songDuration: 100,
            albumTracks: [
                AlbumTrackInfo(id: "t1", title: "One", artistName: "Artist", trackNumber: 1, duration: 60),
                AlbumTrackInfo(id: "t2", title: "Two", artistName: "Artist", trackNumber: 2, duration: 100),
                AlbumTrackInfo(id: "t3", title: "Three", artistName: "Artist", trackNumber: 3, duration: 200)
            ]
        )

        let result = AlbumProgressCalculator.calculate(for: snapshot)
        check(result.method == .fullAlbumDurations, "uses full album durations when every duration is available")
        checkClose(result.percentage, 110.0 / 360.0, "full-duration album percentage")
        check(result.statusLine == "Track 2 of 3 · 31% complete", "full-duration status line")
        check(result.resumeLine == "Resume from 0:50 in Track 2", "full-duration resume line")
        checkClose(result.totalAlbumDuration ?? 0, 360, "total album duration")
    }

    private mutating func testProgressFallbacks() {
        let trackCountResult = AlbumProgressCalculator.calculate(
            for: makeSnapshot(
                trackIdentifier: "t6",
                trackNumber: 6,
                totalTrackCount: 10,
                playbackPosition: 50,
                songDuration: 100,
                albumTracks: []
            )
        )
        check(trackCountResult.method == .trackCountAndSongProgress, "falls back to track count and current song progress")
        checkClose(trackCountResult.percentage, 0.55, "track-count fallback percentage")

        let currentTrackResult = AlbumProgressCalculator.calculate(
            for: makeSnapshot(
                trackIdentifier: "loose",
                trackNumber: nil,
                totalTrackCount: nil,
                playbackPosition: 25,
                songDuration: 100,
                albumTracks: []
            )
        )
        check(currentTrackResult.method == .currentTrackOnly, "falls back to current-track-only progress")
        checkClose(currentTrackResult.percentage, 0.25, "current-track-only percentage")

        let unavailableResult = AlbumProgressCalculator.calculate(
            for: makeSnapshot(
                trackIdentifier: "radio",
                trackNumber: nil,
                totalTrackCount: nil,
                playbackPosition: 25,
                songDuration: nil,
                albumTracks: []
            )
        )
        check(unavailableResult.method == .unavailable, "reports unavailable when no duration or album context exists")
        check(unavailableResult.percentage == 0, "unavailable progress is zero")
    }

    private mutating func testAlbumProgressRecord() {
        let snapshot = makeSnapshot(
            trackIdentifier: "t2",
            musicAppPersistentID: "ABC123",
            trackNumber: 2,
            totalTrackCount: 3,
            playbackPosition: 42,
            songDuration: 100,
            albumTracks: []
        )
        let progress = AlbumProgressCalculator.calculate(for: snapshot)
        let record = AlbumProgressRecord.make(from: snapshot, progress: progress)

        check(record.id == record.albumIdentifier, "record id is album identifier")
        check(record.trackIdentifier == "t2", "record stores track identifier")
        check(record.musicAppPersistentID == "ABC123", "record stores Music.app persistent ID")
        check(record.trackStatus == "Track 2 of 3", "record track status includes total count")
        check(record.progressFraction >= 0 && record.progressFraction <= 1, "record progress fraction is clamped")
    }

    private mutating func testAlbumProgressStore() async {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlbumMarkLogicTests-\(UUID().uuidString)", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let store = AlbumProgressStore(appDirectoryOverride: tempDirectory)
        let older = makeRecord(albumID: "older", title: "Older", progress: 0.4, lastPlayedOffset: -100)
        let newer = makeRecord(albumID: "newer", title: "Newer", progress: 0.6, lastPlayedOffset: -10)
        let finished = makeRecord(albumID: "finished", title: "Finished", progress: 0.99, lastPlayedOffset: 0)

        store.upsert(older, hideCompletedThreshold: 0.95)
        store.upsert(newer, hideCompletedThreshold: 0.95)
        store.upsert(finished, hideCompletedThreshold: 0.95)

        let visible = store.visibleRecords(hideCompletedThreshold: 0.95)
        check(visible.map(\.albumIdentifier) == ["newer", "older"], "store hides completed records and sorts by recent play")

        store.markAsFinished(newer)
        check(store.visibleRecords(hideCompletedThreshold: 0.95).map(\.albumIdentifier) == ["older"], "mark as finished hides record")

        store.remove(older)
        check(store.visibleRecords(hideCompletedThreshold: 0.95).isEmpty, "remove deletes record")

        let reloadedStore = AlbumProgressStore(appDirectoryOverride: tempDirectory)
        check(reloadedStore.records.contains { $0.albumIdentifier == "finished" }, "store reloads JSON records")
    }

    private mutating func testResumeScriptDoesNotFallbackToCurrentPlayback() {
        let script = MusicAppBridge().resumeScript(
            for: MusicAppResumeTarget(
                persistentID: "ABC123",
                trackID: 33509,
                sourceID: 64,
                appleMusicTrackURL: URL(string: "https://music.apple.com/us/album/track/1?i=2"),
                appleMusicAlbumURL: URL(string: "https://music.apple.com/us/album/track/1"),
                appleMusicAlbumTrackURLs: [
                    URL(string: "https://music.apple.com/us/album/track/1?i=2")!,
                    URL(string: "https://music.apple.com/us/album/track/1?i=3")!
                ],
                albumTitle: "Quoted \"Album\"",
                artistName: "Artist",
                trackTitle: "Track",
                trackNumber: 4,
                playbackPosition: 91
            )
        )

        check(script.contains("play targetTrack"), "resume script plays the resolved saved track")
        check(script.contains("play queuePlaylist"), "resume script plays an album queue when available")
        check(script.contains("AlbumMark Resume Queue"), "resume script uses the managed album queue playlist")
        check(script.contains("track id targetMusicTrackID of source id targetSourceID"), "resume script tries saved Music.app URL-track reference")
        check(!script.contains("open location"), "resume script does not hand Apple Music URLs to Music.app")
        check(!script.contains("albumQueueFromAppleMusicURLs"), "resume script does not build a delayed queue from Apple Music track URLs")
        check(!script.contains("findURLTrackByPersistentID"), "resume script does not run the slow older URL-track scan")
        check(script.contains("was not found in Music.app"), "resume script errors when no saved target is found")
        check(!script.contains("\n                play\n"), "resume script does not issue a bare play fallback")
        check(script.contains("Quoted \\\"Album\\\""), "resume script escapes quoted metadata")

        var compileError: NSDictionary?
        let compiled = NSAppleScript(source: script)?.compileAndReturnError(&compileError) ?? false
        check(compiled, "resume script compiles: \(compileError?[NSAppleScript.errorMessage] as? String ?? "unknown error")")
    }

    private mutating func testArtworkScriptCompiles() {
        let script = MusicAppBridge().artworkScript(
            persistentID: "ABC123",
            jpegPath: "/tmp/Album Mark \"Cover\".jpg",
            pngPath: "/tmp/Album Mark \"Cover\".png"
        )

        check(script.contains("raw data of artworkValue"), "artwork script exports original artwork data")
        check(script.contains("ABC123"), "artwork script targets the current persistent ID")
        check(script.contains("\\\"Cover\\\".jpg"), "artwork script escapes quoted output paths")

        var compileError: NSDictionary?
        let compiled = NSAppleScript(source: script)?.compileAndReturnError(&compileError) ?? false
        check(compiled, "artwork script compiles: \(compileError?[NSAppleScript.errorMessage] as? String ?? "unknown error")")
    }

    private func makeSnapshot(
        trackIdentifier: String,
        musicAppPersistentID: String? = nil,
        trackNumber: Int?,
        totalTrackCount: Int?,
        playbackPosition: TimeInterval,
        songDuration: TimeInterval?,
        albumTracks: [AlbumTrackInfo]
    ) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            trackIdentifier: trackIdentifier,
            musicAppPersistentID: musicAppPersistentID,
            musicAppTrackID: 42,
            musicAppSourceID: 64,
            albumIdentifier: "album-id",
            songTitle: "Track",
            artistName: "Artist",
            albumTitle: "Album",
            artworkURL: nil,
            appleMusicTrackURL: URL(string: "https://music.apple.com/us/album/track/1?i=2"),
            appleMusicAlbumURL: URL(string: "https://music.apple.com/us/album/track/1"),
            appleMusicCollectionID: 1,
            appleMusicCatalogTrackID: 2,
            trackNumber: trackNumber,
            totalTrackCount: totalTrackCount,
            playbackPosition: playbackPosition,
            songDuration: songDuration,
            playbackState: .playing,
            albumTracks: albumTracks,
            albumContextIsReliable: trackNumber != nil || totalTrackCount != nil,
            capturedAt: Date()
        )
    }

    private func makeRecord(albumID: String, title: String, progress: Double, lastPlayedOffset: TimeInterval) -> AlbumProgressRecord {
        AlbumProgressRecord(
            albumIdentifier: albumID,
            albumTitle: title,
            artistName: "Artist",
            artworkURLString: nil,
            appleMusicTrackURLString: "https://music.apple.com/us/album/track/1?i=2",
            appleMusicAlbumURLString: "https://music.apple.com/us/album/track/1",
            appleMusicCollectionID: 1,
            appleMusicCatalogTrackID: 2,
            currentTrackTitle: "Track",
            currentTrackNumber: 1,
            totalTrackCount: 10,
            trackIdentifier: "\(albumID)-track",
            musicAppPersistentID: "\(albumID)-pid",
            musicAppTrackID: 42,
            musicAppSourceID: 64,
            playbackPosition: 10,
            trackDuration: 100,
            albumProgressPercentage: progress,
            lastPlayedAt: Date().addingTimeInterval(lastPlayedOffset),
            isFinished: false
        )
    }

    private func finish() -> Never {
        if failures.isEmpty {
            print("AlbumMark logic tests passed")
            exit(0)
        }

        for failure in failures {
            fputs("FAIL: \(failure)\n", stderr)
        }
        exit(1)
    }
}

@main
enum Main {
    static func main() async {
        var runner = LogicTestRunner()
        await runner.run()
    }
}
