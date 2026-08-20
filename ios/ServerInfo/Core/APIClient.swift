import Foundation

/// HTTP-client met mutual TLS. Eén codepad voor alle connectieprofielen:
/// altijd het client-certificaat meesturen, altijd de server valideren tegen
/// de CA die bij koppeling is ontvangen.
final class APIClient: NSObject, @unchecked Sendable {

    private let baseURL: URL
    private let credentials: ServerCredentials
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 300
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    /// Aparte sessie voor de SSE-stream: die mag nooit door een request-timeout
    /// worden afgekapt, de keep-alive bewaakt hem.
    private lazy var streamSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3600
        cfg.timeoutIntervalForResource = 86400
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    init(baseURL: URL, credentials: ServerCredentials) {
        self.baseURL = baseURL
        self.credentials = credentials
        super.init()
    }

    // MARK: - Requests

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        // Bewust niet appendingPathComponent: dat escapet het vraagteken van
        // een querystring tot %3F en levert een 404 op.
        let url = URL(string: path, relativeTo: baseURL) ?? baseURL
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        // Standaard het bearer-schema; achter een proxy met eigen basic auth
        // kan de agent hetzelfde token via X-Server-Info-Token ontvangen.
        req.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        req.setValue(credentials.token, forHTTPHeaderField: "X-Server-Info-Token")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return req
    }

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        let (data, resp) = try await session.data(for: request(path))
        try Self.check(resp, data)
        return try Self.decoder.decode(T.self, from: data)
    }

    @discardableResult
    func post<T: Decodable>(_ path: String, body: Encodable, as type: T.Type) async throws -> T {
        let data = try JSONEncoder().encode(AnyEncodable(body))
        let (out, resp) = try await session.data(for: request(path, method: "POST", body: data))
        try Self.check(resp, out)
        return try Self.decoder.decode(T.self, from: out)
    }

    func delete(_ path: String) async throws {
        let (data, resp) = try await session.data(for: request(path, method: "DELETE"))
        try Self.check(resp, data)
    }

    // MARK: - SSE

    /// Levert samples zolang de stream open is. Afsluiten gebeurt door de
    /// omringende Task te cancellen — SwiftUI's .task doet dat automatisch
    /// wanneer de view verdwijnt.
    func stream(backfill: Int = 60) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = request("v1/stream?backfill=\(backfill)")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, resp) = try await streamSession.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                        throw APIClientError.http((resp as? HTTPURLResponse)?.statusCode ?? 0)
                    }
                    var event = "message"
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.hasPrefix("event:") {
                            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            guard let data = payload.data(using: .utf8),
                                  let sample = try? Self.decoder.decode(Sample.self, from: data)
                            else { continue }
                            continuation.yield(event == "backfill" ? .backfill(sample) : .sample(sample))
                        }
                        // Lege regels en ": keep-alive" worden genegeerd.
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum StreamEvent: Sendable {
        case sample(Sample)
        case backfill(Sample)

        var value: Sample {
            switch self {
            case .sample(let s), .backfill(let s): s
            }
        }
        var isBackfill: Bool { if case .backfill = self { true } else { false } }
    }

    // MARK: - Hulp

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if let apiErr = try? decoder.decode(APIError.self, from: data) {
                throw apiErr
            }
            throw APIClientError.http(http.statusCode)
        }
    }
}

// MARK: - TLS

extension APIClient: URLSessionDelegate, URLSessionTaskDelegate {

    // Sessie-niveau: geldt voor gewone data-taken.
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }

    // Taak-niveau: URLSession.bytes(for:) — de SSE-stream — vraagt de
    // challenge hier op. Zonder deze methode valt de stream terug op de
    // standaardvalidatie en wordt ons eigen CA-certificaat geweigerd.
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }

    private func handle(_ challenge: URLAuthenticationChallenge,
                        _ completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        switch challenge.protectionSpace.authenticationMethod {

        case NSURLAuthenticationMethodClientCertificate:
            // Laag 1: bewijs wie we zijn. Zonder dit komt er geen verbinding.
            // certificates: nil — de identity bevat het leaf-certificaat al.
            // Het nogmaals meegeven levert een dubbele keten op.
            let cred = URLCredential(identity: credentials.identity,
                                     certificates: nil,
                                     persistence: .forSession)
            completionHandler(.useCredential, cred)

        case NSURLAuthenticationMethodServerTrust:
            // Laag 4: valideer de server tegen de CA van déze server. Geen
            // systeem-CA's, geen TOFU — een servercertificaat dat niet door
            // die CA is uitgegeven, wordt geweigerd.
            guard let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            SecTrustSetAnchorCertificates(trust, [credentials.caCertificate] as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }

        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

enum APIClientError: LocalizedError {
    case http(Int)
    case badURL

    var errorDescription: String? {
        switch self {
        case .http(403): "Dit toestel is niet (meer) gekoppeld aan deze server."
        case .http(401): "Het token klopt niet meer. Koppel de server opnieuw."
        case .http(let c): "De server antwoordde met status \(c)."
        case .badURL: "Het serveradres is ongeldig."
        }
    }
}

/// Kleine wrapper zodat `Encodable` als parameter kan worden doorgegeven.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        encodeFunc = { try wrapped.encode(to: $0) }
    }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
