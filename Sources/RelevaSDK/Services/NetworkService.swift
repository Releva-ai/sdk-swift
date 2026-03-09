import Foundation

/// Service for handling network requests
public class NetworkService {

    // MARK: - Types

    /// HTTP methods
    public enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    /// Network request result
    public typealias NetworkResult<T> = Result<T, RelevaError>

    /// Completion handler for network requests
    public typealias CompletionHandler<T> = (NetworkResult<T>) -> Void

    // MARK: - Properties

    /// URL session to use
    private let session: URLSession

    /// Configuration
    private let config: RelevaConfig

    /// Access token for API authentication
    private let accessToken: String

    /// Realm for API endpoint
    private let realm: String

    /// Maximum number of retry attempts
    private var maxRetryAttempts: Int {
        return config.maxRetryAttempts
    }

    /// Request timeout interval
    private var requestTimeout: TimeInterval {
        return config.requestTimeoutInterval
    }

    // MARK: - Initializers

    /// Initialize network service
    /// - Parameters:
    ///   - realm: API realm
    ///   - accessToken: API access token
    ///   - config: SDK configuration
    ///   - session: URLSession to use (defaults to shared)
    public init(
        realm: String,
        accessToken: String,
        config: RelevaConfig,
        session: URLSession = .shared
    ) {
        self.realm = realm
        self.accessToken = accessToken
        self.config = config
        self.session = session
    }

    // MARK: - Base URL

    /// Get the base URL for API requests
    private func getBaseURL() -> String {
        if let customEndpoint = config.customEndpoint {
            return customEndpoint
        }

        if !realm.isEmpty {
            return "https://\(realm).releva.ai"
        }

        return "https://releva.ai"
    }

    // MARK: - Request Building

    /// Build URL request
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - method: HTTP method
    ///   - body: Request body (optional)
    ///   - headers: Additional headers (optional)
    /// - Returns: Configured URLRequest
    private func buildRequest(
        endpoint: String,
        method: HTTPMethod,
        body: Data? = nil,
        headers: [String: String]? = nil
    ) throws -> URLRequest {
        let urlString = getBaseURL() + endpoint
        guard let url = URL(string: urlString) else {
            throw RelevaError.invalidConfiguration("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = requestTimeout

        // Set default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("RelevaSDK-iOS/\(SDKVersion.current)", forHTTPHeaderField: "User-Agent")
        request.setValue("iOS/\(DeviceType.current.rawValue)", forHTTPHeaderField: "X-Platform")

        // Add custom headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Set body if provided
        request.httpBody = body

        return request
    }

    // MARK: - Public Methods

    /// Send a push request to the API
    /// - Parameters:
    ///   - request: Push request data
    ///   - context: Additional context data
    ///   - completion: Completion handler with RelevaResponse
    public func sendPushRequest(
        _ request: [String: Any],
        context: [String: Any],
        completion: @escaping CompletionHandler<RelevaResponse>
    ) {
        let payload = buildPushPayload(request: request, context: context)

        performRequest(
            endpoint: "/api/v0/push",
            method: .post,
            body: payload,
            retryAttempts: maxRetryAttempts
        ) { (result: NetworkResult<Data>) in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(RelevaResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    if self.config.enableDebugLogging {
                        print("RelevaSDK: Failed to decode response: \(error)")
                    }
                    completion(.failure(.invalidResponse("Failed to decode response")))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Register push token
    /// - Parameters:
    ///   - token: Push notification token
    ///   - deviceType: Device type
    ///   - deviceId: Device ID
    ///   - profileId: Profile ID
    ///   - completion: Completion handler
    public func registerPushToken(
        _ token: String,
        deviceType: DeviceType,
        deviceId: String,
        profileId: String?,
        completion: @escaping CompletionHandler<Bool>
    ) {
        var payload: [String: Any] = [
            "pushToken": token,
            "deviceType": deviceType.rawValue,
            "deviceId": deviceId
        ]

        if let profileId = profileId {
            payload["profileId"] = profileId
        }

        performRequest(
            endpoint: "/api/v0/appPush/tokens",
            method: .post,
            body: payload,
            retryAttempts: maxRetryAttempts
        ) { (result: NetworkResult<Data>) in
            switch result {
            case .success:
                completion(.success(true))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Send engagement events
    /// - Parameters:
    ///   - events: Array of engagement events
    ///   - completion: Completion handler
    public func sendEngagementEvents(
        _ events: [EngagementEvent],
        completion: @escaping CompletionHandler<Bool>
    ) {
        // Group events by callback URL
        let groupedEvents = EngagementEvent.groupByCallbackUrl(events)

        let group = DispatchGroup()
        var allSucceeded = true

        for (callbackUrl, urlEvents) in groupedEvents {
            group.enter()

            let payload = urlEvents.map { $0.toDict() }

            performRequest(
                endpoint: callbackUrl,
                method: .post,
                body: payload,
                retryAttempts: 2
            ) { (result: NetworkResult<Data>) in
                if case .failure = result {
                    allSucceeded = false
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(allSucceeded ? .success(true) : .failure(.networkError("Failed to send some events")))
        }
    }

    // MARK: - Private Methods

    /// Perform network request with retry logic
    private func performRequest(
        endpoint: String,
        method: HTTPMethod,
        body: Any? = nil,
        retryAttempts: Int,
        completion: @escaping CompletionHandler<Data>
    ) {
        do {
            var requestBody: Data? = nil
            if let body = body {
                requestBody = try JSONSerialization.data(withJSONObject: body, options: [])
            }

            let request = try buildRequest(
                endpoint: endpoint,
                method: method,
                body: requestBody
            )

            if config.enableDebugLogging {
                print("RelevaSDK: Sending \(method.rawValue) request to \(request.url?.absoluteString ?? "")")
                if let body = body {
                    print("RelevaSDK: Request body: \(body)")
                }
            }

            executeRequest(request, retryAttempts: retryAttempts, completion: completion)

        } catch {
            completion(.failure(.networkError(error.localizedDescription)))
        }
    }

    /// Execute URLRequest with retry logic
    private func executeRequest(
        _ request: URLRequest,
        retryAttempts: Int,
        completion: @escaping CompletionHandler<Data>
    ) {
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Handle network error
            if let error = error {
                if retryAttempts > 0 {
                    if self.config.enableDebugLogging {
                        print("RelevaSDK: Request failed, retrying... (\(retryAttempts) attempts left)")
                    }

                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        self.executeRequest(request, retryAttempts: retryAttempts - 1, completion: completion)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(.networkError(error.localizedDescription)))
                    }
                }
                return
            }

            // Handle HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse("No HTTP response")))
                }
                return
            }

            if self.config.enableDebugLogging {
                print("RelevaSDK: Response status code: \(httpResponse.statusCode)")
            }

            // Handle different status codes
            switch httpResponse.statusCode {
            case 200...299:
                // Success
                guard let data = data else {
                    DispatchQueue.main.async {
                        completion(.failure(.invalidResponse("No data received")))
                    }
                    return
                }

                DispatchQueue.main.async {
                    completion(.success(data))
                }

            case 401:
                // Unauthorized
                DispatchQueue.main.async {
                    completion(.failure(.unauthorized))
                }

            case 500...599:
                // Server error - retry if attempts remaining
                if retryAttempts > 0 {
                    if self.config.enableDebugLogging {
                        print("RelevaSDK: Server error \(httpResponse.statusCode), retrying...")
                    }

                    DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                        self.executeRequest(request, retryAttempts: retryAttempts - 1, completion: completion)
                    }
                } else {
                    let message = String(data: data ?? Data(), encoding: .utf8)
                    DispatchQueue.main.async {
                        completion(.failure(.serverError(httpResponse.statusCode, message)))
                    }
                }

            default:
                // Other errors
                let message = String(data: data ?? Data(), encoding: .utf8)
                DispatchQueue.main.async {
                    completion(.failure(.serverError(httpResponse.statusCode, message)))
                }
            }
        }

        task.resume()
    }

    /// Build push request payload with context
    private func buildPushPayload(request: [String: Any], context: [String: Any]) -> [String: Any] {
        var payload: [String: Any] = [
            "context": context,
            "options": [
                "client": [
                    "vendor": "Releva",
                    "platform": "ios",
                    "version": SDKVersion.current
                ]
            ]
        ]

        // Merge request data into context
        if var contextCopy = payload["context"] as? [String: Any] {
            request.forEach { key, value in
                if key == "page" || key == "product" || key == "events" || key == "profile" {
                    contextCopy[key] = value
                }
            }
            payload["context"] = contextCopy
        }

        return payload
    }
}

// MARK: - Async/Await Support

@available(iOS 15.0, *)
extension NetworkService {

    /// Send push request using async/await
    public func sendPushRequest(
        _ request: [String: Any],
        context: [String: Any]
    ) async throws -> RelevaResponse {
        return try await withCheckedThrowingContinuation { continuation in
            sendPushRequest(request, context: context) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Register push token using async/await
    public func registerPushToken(
        _ token: String,
        deviceType: DeviceType,
        deviceId: String,
        profileId: String?
    ) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            registerPushToken(token, deviceType: deviceType, deviceId: deviceId, profileId: profileId) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Send engagement events using async/await
    public func sendEngagementEvents(_ events: [EngagementEvent]) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            sendEngagementEvents(events) { result in
                continuation.resume(with: result)
            }
        }
    }
}

// MARK: - SDK Version

struct SDKVersion {
    static let current = "1.0.0"
}

// MARK: - Inbox API

extension NetworkService {

    /// Base inbox URL: https://<host>/api/v0/inbox/<accessToken>
    private func inboxBaseUrl(accessToken: String, realm: String) -> String {
        let host: String
        if let custom = config.customEndpoint {
            host = custom
        } else if !realm.isEmpty {
            host = "https://\(realm).releva.ai"
        } else {
            host = "https://releva.ai"
        }
        return "\(host)/api/v0/inbox/\(accessToken)"
    }

    // MARK: Fetch messages (paginated)

    public func inboxFetchMessages(
        userId: String,
        cursor: String?,
        limit: Int = 20,
        accessToken: String,
        realm: String
    ) async -> Result<InboxMessagesResponse, RelevaError> {
        var components = URLComponents(string: inboxBaseUrl(accessToken: accessToken, realm: realm) + "/messages")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            return .failure(.invalidConfiguration("Invalid inbox URL"))
        }

        return await withCheckedContinuation { continuation in
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = config.requestTimeoutInterval
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("RelevaSDK-iOS/\(SDKVersion.current)", forHTTPHeaderField: "User-Agent")

            session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(returning: .failure(.networkError(error.localizedDescription)))
                    return
                }
                guard let data = data, let http = response as? HTTPURLResponse else {
                    continuation.resume(returning: .failure(.invalidResponse("No data")))
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    continuation.resume(returning: .failure(.serverError(http.statusCode, nil)))
                    return
                }
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .millisecondsSince1970
                    let decoded = try decoder.decode(InboxMessagesResponse.self, from: data)
                    continuation.resume(returning: .success(decoded))
                } catch {
                    continuation.resume(returning: .failure(.invalidResponse("Decode error: \(error)")))
                }
            }.resume()
        }
    }

    // MARK: Fetch unread count

    public func inboxFetchUnreadCount(
        userId: String,
        accessToken: String,
        realm: String
    ) async -> Result<Int, RelevaError> {
        guard var components = URLComponents(string: inboxBaseUrl(accessToken: accessToken, realm: realm) + "/unread-count") else {
            return .failure(.invalidConfiguration("Invalid inbox URL"))
        }
        components.queryItems = [URLQueryItem(name: "userId", value: userId)]

        guard let url = components.url else {
            return .failure(.invalidConfiguration("Invalid inbox URL"))
        }

        return await withCheckedContinuation { continuation in
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = config.requestTimeoutInterval
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("RelevaSDK-iOS/\(SDKVersion.current)", forHTTPHeaderField: "User-Agent")

            session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(returning: .failure(.networkError(error.localizedDescription)))
                    return
                }
                guard let data = data, let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    continuation.resume(returning: .failure(.invalidResponse("Bad response")))
                    return
                }
                if let decoded = try? JSONDecoder().decode(InboxUnreadCountResponse.self, from: data) {
                    continuation.resume(returning: .success(decoded.count))
                } else {
                    continuation.resume(returning: .failure(.invalidResponse("Decode error")))
                }
            }.resume()
        }
    }

    // MARK: Mark single message as read

    public func inboxMarkAsRead(
        messageId: String,
        userId: String,
        accessToken: String,
        realm: String
    ) async -> Result<Void, RelevaError> {
        return await inboxPost(
            path: "/messages/\(messageId)/read",
            body: ["userId": userId],
            accessToken: accessToken,
            realm: realm
        )
    }

    // MARK: Mark all as read

    public func inboxMarkAllAsRead(
        userId: String,
        accessToken: String,
        realm: String
    ) async -> Result<Void, RelevaError> {
        return await inboxPost(
            path: "/messages/read-all",
            body: ["userId": userId],
            accessToken: accessToken,
            realm: realm
        )
    }

    // MARK: Delete message

    public func inboxDeleteMessage(
        messageId: String,
        userId: String,
        accessToken: String,
        realm: String
    ) async -> Result<Void, RelevaError> {
        guard let url = URL(string: inboxBaseUrl(accessToken: accessToken, realm: realm) + "/messages/\(messageId)") else {
            return .failure(.invalidConfiguration("Invalid inbox URL"))
        }

        return await withCheckedContinuation { continuation in
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.timeoutInterval = config.requestTimeoutInterval
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("RelevaSDK-iOS/\(SDKVersion.current)", forHTTPHeaderField: "User-Agent")

            if let body = try? JSONSerialization.data(withJSONObject: ["userId": userId]) {
                request.httpBody = body
            }

            session.dataTask(with: request) { _, response, error in
                if let error = error {
                    continuation.resume(returning: .failure(.networkError(error.localizedDescription)))
                    return
                }
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continuation.resume(returning: .failure(.serverError(0, "Delete failed")))
                    return
                }
                continuation.resume(returning: .success(()))
            }.resume()
        }
    }

    // MARK: Track action (click)

    public func inboxTrackAction(
        messageId: String,
        userId: String,
        accessToken: String,
        realm: String
    ) async -> Result<Void, RelevaError> {
        return await inboxPost(
            path: "/messages/\(messageId)/action",
            body: ["userId": userId, "devicePlatform": "ios"],
            accessToken: accessToken,
            realm: realm
        )
    }

    // MARK: Private helper

    private func inboxPost(
        path: String,
        body: [String: Any],
        accessToken: String,
        realm: String
    ) async -> Result<Void, RelevaError> {
        guard let url = URL(string: inboxBaseUrl(accessToken: accessToken, realm: realm) + path) else {
            return .failure(.invalidConfiguration("Invalid inbox URL"))
        }

        return await withCheckedContinuation { continuation in
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = config.requestTimeoutInterval
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("RelevaSDK-iOS/\(SDKVersion.current)", forHTTPHeaderField: "User-Agent")

            if let bodyData = try? JSONSerialization.data(withJSONObject: body) {
                request.httpBody = bodyData
            }

            session.dataTask(with: request) { _, response, error in
                if let error = error {
                    continuation.resume(returning: .failure(.networkError(error.localizedDescription)))
                    return
                }
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continuation.resume(returning: .failure(.serverError(0, "POST failed at \(path)")))
                    return
                }
                continuation.resume(returning: .success(()))
            }.resume()
        }
    }
}