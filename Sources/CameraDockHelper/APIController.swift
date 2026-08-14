import Foundation

final class APIController {
    private let cameraService = CameraService()
    private let presetStore = PresetStore()
    private let lock = NSLock()
    private var startupPresetApplied = false

    init() {
        applyStartupPresetIfNeeded()
    }

    func state() -> CameraState {
        lock.withLock { appState() }
    }

    func rescan() -> CameraState {
        lock.withLock {
            cameraService.rescan()
            applyStartupPresetIfNeeded()
            return appState()
        }
    }

    func route(method: String, path: String, body: Data) -> HTTPResponse {
        lock.withLock {
            if method == "GET", path == "/" {
                guard let url = Bundle.module.url(forResource: "index", withExtension: "html"),
                      let data = try? Data(contentsOf: url) else {
                    return HTTPResponse(
                        status: "500 Internal Server Error",
                        contentType: "text/plain; charset=utf-8",
                        body: Data("Chybí index.html".utf8)
                    )
                }
                return HTTPResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: data)
            }

            if method == "GET", path == "/api/state" {
                return encoded(appState())
            }

            if method == "POST", path == "/api/control" {
                do {
                    let update = try JSONDecoder().decode(ControlUpdate.self, from: body)
                    try cameraService.apply(update)
                    return encoded(appState())
                } catch {
                    return .json(status: "400 Bad Request", ["error": error.localizedDescription])
                }
            }

            if method == "POST", path == "/api/rescan" {
                cameraService.rescan()
                applyStartupPresetIfNeeded()
                return encoded(appState())
            }

            if method == "POST", path == "/api/reset" {
                do {
                    try cameraService.reset()
                    return encoded(appState())
                } catch {
                    return .json(status: "400 Bad Request", ["error": error.localizedDescription])
                }
            }

            if method == "POST", path == "/api/presets/create" {
                return handlePreset(body) { request in
                    guard let name = request.name else { throw PresetError.missingName }
                    try presetStore.create(
                        panel: request.panel,
                        name: name,
                        values: try cameraService.snapshot(panel: request.panel)
                    )
                }
            }

            if method == "POST", path == "/api/presets/save" {
                return handlePreset(body) { request in
                    guard let id = request.id else { throw PresetError.missingPreset }
                    try presetStore.save(
                        panel: request.panel,
                        id: id,
                        values: try cameraService.snapshot(panel: request.panel)
                    )
                }
            }

            if method == "POST", path == "/api/presets/load" {
                return handlePreset(body) { request in
                    guard let id = request.id else { throw PresetError.missingPreset }
                    let preset = try presetStore.preset(byId: id)
                    try cameraService.applyPreset(preset.values)
                }
            }

            if method == "POST", path == "/api/presets/delete" {
                return handlePreset(body) { request in
                    guard let id = request.id else { throw PresetError.missingPreset }
                    try presetStore.delete(panel: request.panel, id: id)
                }
            }

            return .json(status: "404 Not Found", ["error": "Nenalezeno"])
        }
    }

    private func appState() -> CameraState {
        var state = cameraService.state()
        state.presets = presetStore.library
        return state
    }

    private func applyStartupPresetIfNeeded() {
        guard !startupPresetApplied else { return }
        let state = cameraService.state()
        guard state.connected else { return }
        guard let values = CameraService.buildRRCBaseValues(controls: state.controls) else { return }

        presetStore.ensureStartupPreset(values: values)
        guard let preset = presetStore.startupPreset() else { return }
        try? cameraService.applyPreset(preset.values)
        startupPresetApplied = true
    }

    private func handlePreset(_ body: Data, _ action: (PresetRequest) throws -> Void) -> HTTPResponse {
        do {
            let request = try JSONDecoder().decode(PresetRequest.self, from: body)
            try action(request)
            return encoded(appState())
        } catch {
            return .json(status: "400 Bad Request", ["error": error.localizedDescription])
        }
    }

    private func encoded<T: Encodable>(_ value: T) -> HTTPResponse {
        do {
            let data = try JSONEncoder().encode(value)
            return HTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: data)
        } catch {
            return .json(status: "500 Internal Server Error", ["error": error.localizedDescription])
        }
    }
}
