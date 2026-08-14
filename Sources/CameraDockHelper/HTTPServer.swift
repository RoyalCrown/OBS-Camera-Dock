import Foundation
import Network

struct HTTPResponse {
    let status: String
    let contentType: String
    let body: Data

    static func json(status: String = "200 OK", _ object: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }
}

final class HTTPServer {
    typealias Handler = (_ method: String, _ path: String, _ body: Data) -> HTTPResponse

    private let queue = DispatchQueue(label: "cz.obs-camera-dock.http")
    private let handler: Handler
    private var listener: NWListener?
    let port: UInt16

    init(port: UInt16, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        let endpointPort = NWEndpoint.Port(rawValue: port)!
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receive(on: connection, accumulated: Data())
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                fputs("OBS Camera Dock: http://127.0.0.1:\(self.port)/\n", stderr)
            } else if case let .failed(error) = state {
                fputs("HTTP server failed: \(error)\n", stderr)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var request = accumulated
            if let data { request.append(data) }

            if self.isCompleteHTTPRequest(request) || complete {
                self.respond(to: request, on: connection)
            } else if error == nil {
                self.receive(on: connection, accumulated: request)
            } else {
                connection.cancel()
            }
        }
    }

    private func isCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8),
              let headerEnd = text.range(of: "\r\n\r\n") else { return false }
        let header = String(text[..<headerEnd.lowerBound])
        let contentLength = header
            .split(separator: "\n")
            .first(where: { $0.lowercased().hasPrefix("content-length:") })
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        let bodyLength = text[headerEnd.upperBound...].utf8.count
        return bodyLength >= contentLength
    }

    private func respond(to requestData: Data, on connection: NWConnection) {
        guard let request = String(data: requestData, encoding: .utf8),
              let headerEnd = request.range(of: "\r\n\r\n") else {
            send(HTTPResponse.json(status: "400 Bad Request", ["error": "Neplatný HTTP požadavek"]), on: connection)
            return
        }

        let header = String(request[..<headerEnd.lowerBound])
        let requestLine = header.split(separator: "\n", maxSplits: 1).first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else {
            send(HTTPResponse.json(status: "400 Bad Request", ["error": "Neplatný HTTP požadavek"]), on: connection)
            return
        }

        let method = String(requestLine[0])
        let rawPath = String(requestLine[1])
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        let body = Data(request[headerEnd.upperBound...].utf8)

        if method == "OPTIONS" {
            send(HTTPResponse(status: "204 No Content", contentType: "text/plain", body: Data()), on: connection)
            return
        }
        send(handler(method, path, body), on: connection)
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        var head = "HTTP/1.1 \(response.status)\r\n"
        head += "Content-Type: \(response.contentType)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Headers: Content-Type\r\n"
        head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"

        var payload = Data(head.utf8)
        payload.append(response.body)
        connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
    }
}
