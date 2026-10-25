import Foundation

/// Modelos do Whisper ficam dentro do container do app (Application Support).
/// O app não baixa nada: o usuário importa uma pasta baixada uma única vez pelo `scripts/fetch-model.sh`.
enum ModelStore {
    static let requiredItems = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc", "tokenizer.json"]

    static var modelsRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Gravador/Models", isDirectory: true)
    }

    static func isValidModel(_ folder: URL) -> Bool {
        requiredItems.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// Modelos importados, por nome de pasta.
    static func installedModels() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(at: modelsRoot, includingPropertiesForKeys: nil)) ?? []
        return items.filter(isValidModel).map(\.lastPathComponent).sorted()
    }

    static func folder(named name: String) -> URL {
        modelsRoot.appendingPathComponent(name, isDirectory: true)
    }

    /// Copia uma pasta de modelo escolhida pelo usuário para dentro do container.
    static func importModel(from source: URL) throws -> String {
        guard isValidModel(source) else { throw ModelStoreError.invalidFolder }
        let fm = FileManager.default
        try fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        let name = source.lastPathComponent
        let destination = folder(named: name)
        let temporary = modelsRoot.appendingPathComponent(".\(name).importando", isDirectory: true)
        try? fm.removeItem(at: temporary)
        try fm.copyItem(at: source, to: temporary)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: temporary, to: destination)
        return name
    }

    static func remove(named name: String) throws {
        try FileManager.default.removeItem(at: folder(named: name))
    }
}

enum ModelStoreError: LocalizedError {
    case invalidFolder

    var errorDescription: String? {
        "A pasta escolhida não parece um modelo do WhisperKit. Ela precisa conter \(ModelStore.requiredItems.joined(separator: ", ")). Use scripts/fetch-model.sh para baixar."
    }
}
