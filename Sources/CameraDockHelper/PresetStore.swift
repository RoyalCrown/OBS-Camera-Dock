import Foundation

struct PresetValue: Codable {
    var value: Int?
    var enabled: Bool?
}

struct Preset: Codable {
    var id: String
    var name: String
    var values: [String: PresetValue]
}

struct PanelPresets: Codable {
    var items: [Preset] = []
    var selectedId: String?
}

struct PresetLibrary: Codable {
    var expo = PanelPresets()
    var obraz = PanelPresets()
    var optika = PanelPresets()
    var startupPresetId: String? = CameraService.startupPresetID
}

struct PresetRequest: Decodable {
    let panel: String
    let id: String?
    let name: String?
}

enum PresetError: LocalizedError {
    case unknownPanel
    case missingName
    case missingPreset

    var errorDescription: String? {
        switch self {
        case .unknownPanel:
            return "Neznámý panel."
        case .missingName:
            return "Zadejte název presetu."
        case .missingPreset:
            return "Vyberte preset."
        }
    }
}

final class PresetStore {
    static let panels = ["expo", "obraz", "optika"]

    private let url: URL
    private(set) var library = PresetLibrary()

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OBS Camera Dock", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        url = root.appendingPathComponent("presets.json")
        load()
    }

    func create(panel: String, name: String, values: [String: PresetValue]) throws {
        try validate(panel)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PresetError.missingName }
        var box = panelPresets(panel)
        let preset = Preset(id: UUID().uuidString, name: trimmed, values: values)
        box.items.append(preset)
        box.selectedId = preset.id
        setPanel(panel, box)
        save()
    }

    func save(panel: String, id: String, values: [String: PresetValue]) throws {
        try validate(panel)
        var box = panelPresets(panel)
        guard let index = box.items.firstIndex(where: { $0.id == id }) else { throw PresetError.missingPreset }
        box.items[index].values = values
        box.selectedId = id
        setPanel(panel, box)
        save()
    }

    func delete(panel: String, id: String) throws {
        try validate(panel)
        var box = panelPresets(panel)
        guard box.items.contains(where: { $0.id == id }) else { throw PresetError.missingPreset }
        box.items.removeAll { $0.id == id }
        if box.selectedId == id {
            box.selectedId = box.items.last?.id
        }
        setPanel(panel, box)
        save()
    }

    func preset(panel: String, id: String) throws -> Preset {
        try validate(panel)
        var box = panelPresets(panel)
        guard let preset = box.items.first(where: { $0.id == id }) else { throw PresetError.missingPreset }
        box.selectedId = id
        setPanel(panel, box)
        save()
        return preset
    }

    func ensureStartupPreset(values: [String: PresetValue]) {
        if let location = startupPresetLocation() {
            var box = panelPresets(location.panel)
            box.items[location.index].values = values
            box.selectedId = CameraService.startupPresetID
            setPanel(location.panel, box)
            library.startupPresetId = CameraService.startupPresetID
            save()
            return
        }

        var box = library.expo
        let preset = Preset(
            id: CameraService.startupPresetID,
            name: CameraService.startupPresetName,
            values: values
        )
        box.items.insert(preset, at: 0)
        box.selectedId = preset.id
        library.expo = box
        library.startupPresetId = preset.id
        save()
    }

    func preset(byId id: String) throws -> Preset {
        if let location = presetLocation(id: id) {
            var box = panelPresets(location.panel)
            box.selectedId = id
            setPanel(location.panel, box)
            save()
            return box.items[location.index]
        }
        throw PresetError.missingPreset
    }

    private func startupPresetLocation() -> (panel: String, index: Int)? {
        presetLocation(id: CameraService.startupPresetID)
    }

    private func presetLocation(id: String) -> (panel: String, index: Int)? {
        for panel in Self.panels {
            if let index = panelPresets(panel).items.firstIndex(where: { $0.id == id }) {
                return (panel, index)
            }
        }
        return nil
    }

    func startupPreset() -> Preset? {
        let id = library.startupPresetId ?? CameraService.startupPresetID
        for panel in Self.panels {
            if let preset = panelPresets(panel).items.first(where: { $0.id == id }) {
                return preset
            }
        }
        return library.expo.items.first(where: { $0.name == CameraService.startupPresetName })
    }

    private func validate(_ panel: String) throws {
        guard Self.panels.contains(panel) else { throw PresetError.unknownPanel }
    }

    private func panelPresets(_ panel: String) -> PanelPresets {
        switch panel {
        case "obraz": return library.obraz
        case "optika": return library.optika
        default: return library.expo
        }
    }

    private func setPanel(_ panel: String, _ box: PanelPresets) {
        switch panel {
        case "obraz": library.obraz = box
        case "optika": library.optika = box
        default: library.expo = box
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PresetLibrary.self, from: data) else { return }
        library = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(library) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
