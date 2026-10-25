import Foundation

/// Grava a transcrição em modo append (`transcricao.md` legível + `transcricao.jsonl` estruturado),
/// para que um crash nunca perca o que já foi transcrito.
public final class TranscriptWriter {
    public static let markdownName = "transcricao.md"
    public static let jsonlName = "transcricao.jsonl"

    public let folder: URL
    public let title: String
    public let startedAt: Date
    private let markdown: FileHandle
    private let jsonl: FileHandle
    private let encoder: JSONEncoder
    private var finished = false

    public init(folder: URL, title: String, startedAt: Date) throws {
        self.folder = folder
        self.title = title
        self.startedAt = startedAt
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let mdURL = folder.appendingPathComponent(Self.markdownName)
        let jsonURL = folder.appendingPathComponent(Self.jsonlName)

        let isNew = !fm.fileExists(atPath: mdURL.path)
        if isNew {
            try Data(Self.header(title: title, startedAt: startedAt).utf8).write(to: mdURL)
        }
        if !fm.fileExists(atPath: jsonURL.path) {
            fm.createFile(atPath: jsonURL.path, contents: nil)
        }
        markdown = try FileHandle(forWritingTo: mdURL)
        jsonl = try FileHandle(forWritingTo: jsonURL)
        try markdown.seekToEnd()
        try jsonl.seekToEnd()

        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    deinit {
        if !finished { try? markdown.close() }
        try? jsonl.close()
    }

    public func append(_ segment: TranscriptSegment) throws {
        try markdown.write(contentsOf: Data(Self.markdownLine(segment).utf8))
        var json = try encoder.encode(segment)
        json.append(0x0A)
        try jsonl.write(contentsOf: json)
    }

    /// Fecha a transcrição. Como as duas trilhas são transcritas fora de ordem, o markdown final
    /// é reescrito em ordem cronológica a partir do jsonl.
    public func finish(endedAt: Date, duration: TimeInterval, note: String? = nil) throws {
        guard !finished else { return }
        finished = true
        try jsonl.synchronize()
        try markdown.close()
        let segments = Self.readSegments(in: folder).sorted { $0.start < $1.start }
        var text = Self.header(title: title, startedAt: startedAt)
        for segment in segments { text += Self.markdownLine(segment) }
        text += "---\n_Fim: \(Self.headerDate.string(from: endedAt)) · duração \(TimeFormatting.clock(duration))_\n"
        if let note { text += "\n_\(note)_\n" }
        try Data(text.utf8).write(to: folder.appendingPathComponent(Self.markdownName), options: .atomic)
    }

    static func header(title: String, startedAt: Date) -> String {
        "# \(title)\n\n_Início: \(headerDate.string(from: startedAt))_\n\n"
    }

    static func markdownLine(_ segment: TranscriptSegment) -> String {
        "**[\(TimeFormatting.clock(segment.start))] \(segment.track.speakerLabel):** \(segment.text)\n\n"
    }

    /// Lê os trechos já gravados (para reabrir uma reunião ou retomar após crash).
    public static func readSegments(in folder: URL) -> [TranscriptSegment] {
        let url = folder.appendingPathComponent(jsonlName)
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { line in
            try? decoder.decode(TranscriptSegment.self, from: Data(line.utf8))
        }
    }

    static let headerDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f
    }()
}

public enum MeetingFolderNaming {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "yyyy-MM-dd HH'h'mm"
        return f
    }()

    /// `2026-10-25 14h30 - Zoom`, com sufixo ` (2)` se já existir.
    public static func folder(in root: URL, startedAt: Date, label: String, fileManager: FileManager = .default) -> URL {
        let safeLabel = label.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = "\(formatter.string(from: startedAt)) - \(safeLabel)"
        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base) (\(n))", isDirectory: true)
            n += 1
        }
        return candidate
    }

    public static func title(startedAt: Date, label: String) -> String {
        "Reunião \(label) — \(TranscriptWriter.headerDate.string(from: startedAt))"
    }
}
