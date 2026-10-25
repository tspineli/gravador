import Foundation
import GravadorCore

/// Reunião salva na pasta de saída.
struct SavedMeeting: Identifiable, Hashable {
    let folder: URL
    let date: Date

    var id: URL { folder }
    var name: String { folder.lastPathComponent }
    var transcriptURL: URL { folder.appendingPathComponent(TranscriptWriter.markdownName) }
}

enum MeetingLibrary {
    static func meetings(in root: URL) -> [SavedMeeting] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return items.compactMap { url -> SavedMeeting? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true,
                  FileManager.default.fileExists(atPath: url.appendingPathComponent(TranscriptWriter.jsonlName).path)
            else { return nil }
            return SavedMeeting(folder: url, date: values?.creationDate ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }
}
