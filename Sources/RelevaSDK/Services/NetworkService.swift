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

    /// Runtime endpoint override (set via setEndpointOverride)
    private var endpointOverride: String?

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

    // MARK: - Endpoint Override

    /// Set a runtime endpoint override (e.g. ngrok URL for local development)
    /// - Parameter url: The override URL, or nil to clear
    public func setEndpointOverride(_ url: String?) {
        self.endpointOverride = url
        if config.enableDebugLogging {
            if let url = url {
                print("RelevaSDK: Endpoint override set to '\(url)'")
            } else {
                print("RelevaSDK: Endpoint override cleared")
            }
        }
    }

    // MARK: - Base URL

    /// Get the base URL for API requests
    func getBaseURL() -> String {
        if let override = endpointOverride {
            return override
        }

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
                    let response = try RelevaResponse.from(jsonData: data)
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

    /// Send engagement events by firing each callback URL with a simple GET request.
    /// The backend registers the click when the callback URL is fetched — no JSON body needed.
    /// - Parameters:
    ///   - events: Array of engagement events
    ///   - completion: Completion handler
    public func sendEngagementEvents(
        _ events: [EngagementEvent],
        completion: @escaping CompletionHandler<Bool>
    ) {
        // Deduplicate callback URLs (multiple events may share the same URL)
        let uniqueCallbackUrls = Set(events.compactMap { $0.callbackUrl })

        let group = DispatchGroup()
        var allSucceeded = true

        for callbackUrl in uniqueCallbackUrls {
            guard let url = URL(string: callbackUrl) else {
                if config.enableDebugLogging {
                    print("RelevaSDK: Invalid callback URL, skipping: \(callbackUrl)")
                }
                continue
            }

            group.enter()

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = requestTimeout

            if config.enableDebugLogging {
                print("RelevaSDK: Firing callback URL: \(callbackUrl)")
            }

            let task = session.dataTask(with: request) { [weak self] _, response, error in
                if let error = error {
                    if self?.config.enableDebugLogging == true {
                        print("RelevaSDK: Callback URL failed: \(error.localizedDescription)")
                    }
                    allSucceeded = false
                } else if let httpResponse = response as? HTTPURLResponse {
                    if self?.config.enableDebugLogging == true {
                        print("RelevaSDK: Callback URL response: \(httpResponse.statusCode)")
                    }
                    if httpResponse.statusCode >= 400 {
                        allSucceeded = false
                    }
                }
                group.leave()
            }
            task.resume()
        }

        group.notify(queue: .main) {
            completion(allSucceeded ? .success(true) : .failure(.networkError("Failed to send some events")))
        }
    }

    // MARK: - Banner Tracking

    /// Send banner impression
    public func sendBannerImpression(
        _ payload: [String: Any],
        completion: @escaping CompletionHandler<Bool>
    ) {
        performRequest(
            endpoint: "/api/v0/impressions",
            method: .post,
            body: payload,
            retryAttempts: 2
        ) { (result: NetworkResult<Data>) in
            switch result {
            case .success:
                completion(.success(true))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Send banner action (click, close, etc.)
    public func sendBannerAction(
        _ payload: [String: Any],
        completion: @escaping CompletionHandler<Bool>
    ) {
        performRequest(
            endpoint: "/api/v0/push/events",
            method: .post,
            body: payload,
            retryAttempts: 2
        ) { (result: NetworkResult<Data>) in
            switch result {
            case .success:
                completion(.success(true))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - NPS

    /// Submit NPS survey response
    public func sendNpsSubmission(
        _ payload: [String: Any],
        token: String,
        completion: @escaping CompletionHandler<Bool>
    ) {
        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        performRequest(
            endpoint: "/api/v0/nps/\(encodedToken)/submissions",
            method: .post,
            body: payload,
            retryAttempts: 1
        ) { (result: NetworkResult<Data>) in
            switch result {
            case .success:
                completion(.success(true))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Inbox

    /// Fetch inbox messages
    public func fetchInboxMessages(
        userId: String,
        limit: Int = 20,
        cursor: String? = nil,
        completion: @escaping CompletionHandler<[String: Any]>
    ) {
        var endpoint = "/api/v0/inbox/messages"
        endpoint += "?userId=\(userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId)"
        endpoint += "&limit=\(limit)"
        if let cursor = cursor {
            endpoint += "&cursor=\(cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cursor)"
        }

        performRequest(endpoint: endpoint, method: .get, retryAttempts: 1) { (result: NetworkResult<Data>) in
            switch result {
            case .success(let data):
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(.invalidResponse("Invalid inbox JSON")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Fetch inbox unread count
    public func fetchInboxUnreadCount(
        userId: String,
        completion: @escaping CompletionHandler<Int>
    ) {
        let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId
        let endpoint = "/api/v0/inbox/unread-count?userId=\(encodedUserId)"

        performRequest(endpoint: endpoint, method: .get, retryAttempts: 1) { (result: NetworkResult<Data>) in
            switch result {
            case .success(let data):
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let count = (json["count"] as? NSNumber)?.intValue ?? 0
                    completion(.success(count))
                } else {
                    completion(.failure(.invalidResponse("Unread count fetch failed")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Mark inbox message as read
    public func inboxMarkAsRead(
        messageId: String,
        userId: String,
        completion: @escaping CompletionHandler<Bool>
    ) {
        performRequest(
            endpoint: "/api/v0/inbox/messages/\(messageId)/read",
            method: .post,
            body: ["userId": userId],
            retryAttempts: 1
        ) { (result: NetworkResult<Data>) in
            switch result {
            case .success: completion(.success(true))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    /// Mark all inbox messages as read
    public func inboxMarkAllAsRead(
        userId: String,
        completion: @escaping CompletionHandler<Bool>
    ) {
        performRequest(
            endpoint: "/api/v0/inbox/messages/read-all",
            method: .post,
            body: ["userId": userId],
            retryAttempts: 1
        ) { (result: NetworkResult<Data>) in
            switch result {
            case .success: completion(.success(true))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    /// Delete inbox message
    public func inboxDeleteMessage(
        messageId: String,
        userId: String,
        completion: @escaping CompletionHandler<Bool>
    ) {
        performRequest(
            endpoint: "/api/v0/inbox/messages/\(messageId)",
            method: .delete,
            body: ["userId": userId],
            retryAttempts: 1
        ) { (result: NetworkResult<Data>) in
            switch result {
            case .success: completion(.success(true))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    /// Track inbox message action
    public func inboxTrackAction(
        messageId: String,
        userId: String,
        completion: @escaping CompletionHandler<Bool>
    ) {
        performRequest(
            endpoint: "/api/v0/inbox/messages/\(messageId)/action",
            method: .post,
            body: ["userId": userId, "devicePlatform": "ios"],
            retryAttempts: 0
        ) { (result: NetworkResult<Data>) in
            switch result {
            case .success: completion(.success(true))
            case .failure(let error): completion(.failure(error))
            }
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
    static let current = "1.1.0"
}