import Foundation

final class APIController {
    private let cameraService = CameraService()
    private let lock = NSLock()

    func state() -> CameraState {
        lock.withLock { cameraService.state() }
    }

    func rescan() -> CameraState {
        lock.withLock {
            cameraService.rescan()
            return cameraService.state()
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
                return encoded(cameraService.state())
            }

            if method == "POST", path == "/api/control" {
                do {
                    let update = try JSONDecoder().decode(ControlUpdate.self, from: body)
                    try cameraService.apply(update)
                    return encoded(cameraService.state())
                } catch {
                    return .json(status: "400 Bad Request", ["error": error.localizedDescription])
                }
            }

            if method == "POST", path == "/api/rescan" {
                cameraService.rescan()
                return encoded(cameraService.state())
            }

            if method == "POST", path == "/api/reset" {
                do {
                    try cameraService.reset()
                    return encoded(cameraService.state())
                } catch {
                    return .json(status: "400 Bad Request", ["error": error.localizedDescription])
                }
            }

            return .json(status: "404 Not Found", ["error": "Nenalezeno"])
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
