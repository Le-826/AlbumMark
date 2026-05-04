import Foundation
import Combine

@MainActor
final class AlbumProgressStore: ObservableObject {
    @Published private(set) var records: [AlbumProgressRecord] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default, appDirectoryOverride: URL? = nil) {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let appDirectory = appDirectoryOverride
            ?? supportDirectory.appendingPathComponent("AlbumMark", isDirectory: true)
        fileURL = appDirectory.appendingPathComponent("progress-records.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            try load()
        } catch {
            records = []
            print("AlbumMark store load failed: \(error.localizedDescription)")
        }
    }

    func visibleRecords(hideCompletedThreshold: Double) -> [AlbumProgressRecord] {
        records
            .filter { !$0.isFinished && $0.progressFraction < hideCompletedThreshold }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    func upsert(_ record: AlbumProgressRecord, hideCompletedThreshold: Double) {
        var updatedRecord = record
        if updatedRecord.progressFraction >= hideCompletedThreshold {
            updatedRecord.isFinished = true
        }

        if let index = records.firstIndex(where: { $0.albumIdentifier == updatedRecord.albumIdentifier }) {
            records[index] = updatedRecord
        } else {
            records.append(updatedRecord)
        }

        saveImmediately()
    }

    func markAsFinished(_ record: AlbumProgressRecord) {
        guard let index = records.firstIndex(where: { $0.albumIdentifier == record.albumIdentifier }) else { return }
        records[index].isFinished = true
        records[index].albumProgressPercentage = max(records[index].albumProgressPercentage, 1)
        saveImmediately()
    }

    func remove(_ record: AlbumProgressRecord) {
        records.removeAll { $0.albumIdentifier == record.albumIdentifier }
        saveImmediately()
    }

    func saveImmediately() {
        do {
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("AlbumMark store save failed: \(error.localizedDescription)")
        }
    }

    private func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }

        let data = try Data(contentsOf: fileURL)
        records = try decoder.decode([AlbumProgressRecord].self, from: data)
    }
}
