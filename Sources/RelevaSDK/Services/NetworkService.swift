import Foundation

/// Service for handling network requests.
///
/// Deliberately *not* `@MainActor`. Every method here is a nonisolated `async` function, so
/// its body runs on the cooperative pool even when awaited from `@MainActor RelevaClient`
/// (SE-0338: a nonisolated async function does not inherit the caller's actor). That is what
/// keeps request encoding and response decoding off the main thread — see the `@MainActor`
/// audit notes in CHANGELOG 5.0.0.
public class NetworkService {
    // MARK: - Types

    /// HTTP methods
    public enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

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
        config.maxRetryAttempts
    }

    /// Request timeout interval
    private var requestTimeout: TimeInterval {
        config.requestTimeoutInterval
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
    /// - Returns: The decoded API response
    public func sendPushRequest(
        _ request: [String: Any],
        context: [String: Any]
    ) async throws -> RelevaResponse {
        let payload = buildPushPayload(request: request, context: context)

        let data = try await performRequest(
            endpoint: "/api/v0/push",
            method: .post,
            body: payload,
            retryAttempts: maxRetryAttempts
        )

        do {
            return try RelevaResponse.from(jsonData: data)
        } catch {
            if config.enableDebugLogging {
                print("RelevaSDK: Failed to decode response: \(error)")
            }
            throw RelevaError.invalidResponse("Failed to decode response")
        }
    }

    /// Register push token
    /// - Parameters:
    ///   - token: Push notification token
    ///   - deviceType: Device type
    ///   - deviceId: Device ID
    ///   - profileId: Profile ID
    public func registerPushToken(
        _ token: String,
        deviceType: DeviceType,
        deviceId: String,
        profileId: String?
    ) async throws {
        var payload: [String: Any] = [
            "pushToken": token,
            "deviceType": deviceType.rawValue,
            "deviceId": deviceId
        ]

        if let profileId = profileId {
            payload["profileId"] = profileId
        }

        _ = try await performRequest(
            endpoint: "/api/v0/appPush/tokens",
            method: .post,
            body: payload,
            retryAttempts: maxRetryAttempts
        )
    }

    /// Send engagement events by firing each callback URL with a simple GET request.
    /// The backend registers the click when the callback URL is fetched — no JSON body needed.
    ///
    /// Throws `RelevaError.networkError` if *any* callback failed, which is what the caller
    /// needs to decide whether the batch may be dropped from the pending queue.
    /// - Parameter events: Array of engagement events
    public func sendEngagementEvents(_ events: [EngagementEvent]) async throws {
        // Deduplicate callback URLs (multiple events may share the same URL)
        let uniqueCallbackUrls = Set(events.compactMap { $0.callbackUrl })

        // The child tasks each return their own verdict and the group folds them together, so
        // there is no shared mutable flag to guard — that is what replaced `CallbackOutcome`.
        let allSucceeded = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for callbackUrl in uniqueCallbackUrls {
                guard let url = URL(string: callbackUrl) else {
                    if config.enableDebugLogging {
                        print("RelevaSDK: Invalid callback URL, skipping: \(callbackUrl)")
                    }
                    continue
                }

                if config.enableDebugLogging {
                    print("RelevaSDK: Firing callback URL: \(callbackUrl)")
                }

                group.addTask { await self.fireEngagementCallback(url) }
            }

            var succeeded = true
            for await callbackSucceeded in group where !callbackSucceeded {
                succeeded = false
            }
            return succeeded
        }

        guard allSucceeded else {
            throw RelevaError.networkError("Failed to send some events")
        }
    }

    /// Fire one engagement callback. Returns whether it counted as a success.
    private func fireEngagementCallback(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout

        do {
            let (_, response) = try await session.data(for: request)
            // A non-HTTP response carries no status to judge; the DispatchGroup version this
            // replaced also let that case through as a success.
            guard let httpResponse = response as? HTTPURLResponse else { return true }

            if config.enableDebugLogging {
                print("RelevaSDK: Callback URL response: \(httpResponse.statusCode)")
            }
            return httpResponse.statusCode < 400
        } catch {
            if config.enableDebugLogging {
                print("RelevaSDK: Callback URL failed: \(error.localizedDescription)")
            }
            return false
        }
    }

    // MARK: - Banner Tracking

    /// Send banner impression
    public func sendBannerImpression(_ payload: [String: Any]) async throws {
        _ = try await performRequest(
            endpoint: "/api/v0/impressions",
            method: .post,
            body: payload,
            retryAttempts: 2
        )
    }

    /// Send a push event action (banner click/close, story impression/click, etc.)
    public func sendPushEvent(_ payload: [String: Any]) async throws {
        _ = try await performRequest(
            endpoint: "/api/v0/push/events",
            method: .post,
            body: payload,
            retryAttempts: 2
        )
    }

    /// Send banner action (click, close, etc.) — convenience alias for sendPushEvent
    public func sendBannerAction(_ payload: [String: Any]) async throws {
        try await sendPushEvent(payload)
    }

    // MARK: - NPS

    /// Submit NPS survey response
    public func sendNpsSubmission(_ payload: [String: Any], token: String) async throws {
        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        _ = try await performRequest(
            endpoint: "/api/v0/nps/\(encodedToken)/submissions",
            method: .post,
            body: payload,
            retryAttempts: 1
        )
    }

    // MARK: - Inbox

    /// Fetch inbox messages
    public func fetchInboxMessages(
        userId: String,
        limit: Int = 20,
        cursor: String? = nil
    ) async throws -> [String: Any] {
        var endpoint = "/api/v0/inbox/messages"
        endpoint += "?userId=\(userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId)"
        endpoint += "&limit=\(limit)"
        if let cursor = cursor {
            endpoint += "&cursor=\(cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cursor)"
        }

        let data = try await performRequest(endpoint: endpoint, method: .get, retryAttempts: 1)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RelevaError.invalidResponse("Invalid inbox JSON")
        }
        return json
    }

    /// Fetch inbox unread count
    public func fetchInboxUnreadCount(userId: String) async throws -> Int {
        let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId
        let endpoint = "/api/v0/inbox/unread-count?userId=\(encodedUserId)"

        let data = try await performRequest(endpoint: endpoint, method: .get, retryAttempts: 1)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RelevaError.invalidResponse("Unread count fetch failed")
        }
        return (json["count"] as? NSNumber)?.intValue ?? 0
    }

    /// Mark inbox message as read
    public func inboxMarkAsRead(messageId: String, userId: String) async throws {
        _ = try await performRequest(
            endpoint: "/api/v0/inbox/messages/\(messageId)/read",
            method: .post,
            body: ["userId": userId],
            retryAttempts: 1
        )
    }

    /// Mark all inbox messages as read
    public func inboxMarkAllAsRead(userId: String) async throws {
        _ = try await performRequest(
            endpoint: "/api/v0/inbox/messages/read-all",
            method: .post,
            body: ["userId": userId],
            retryAttempts: 1
        )
    }

    /// Delete inbox message
    public func inboxDeleteMessage(messageId: String, userId: String) async throws {
        _ = try await performRequest(
            endpoint: "/api/v0/inbox/messages/\(messageId)",
            method: .delete,
            body: ["userId": userId],
            retryAttempts: 1
        )
    }

    /// Track inbox message action
    public func inboxTrackAction(messageId: String, userId: String) async throws {
        _ = try await performRequest(
            endpoint: "/api/v0/inbox/messages/\(messageId)/action",
            method: .post,
            body: ["userId": userId, "devicePlatform": "ios"],
            retryAttempts: 0
        )
    }

    // MARK: - Private Methods

    /// Serialize the body, build the request and run it with retry logic.
    private func performRequest(
        endpoint: String,
        method: HTTPMethod,
        body: Any? = nil,
        retryAttempts: Int
    ) async throws -> Data {
        let request: URLRequest
        do {
            var requestBody: Data?
            if let body = body {
                requestBody = try JSONSerialization.data(withJSONObject: body, options: [])
            }

            request = try buildRequest(
                endpoint: endpoint,
                method: method,
                body: requestBody
            )
        } catch {
            // Serialization and URL-building failures have always surfaced as `.networkError`,
            // including the `.invalidConfiguration` that `buildRequest` throws. Preserved rather
            // than corrected, because callers switch on the kind.
            throw RelevaError.networkError(error.localizedDescription)
        }

        if config.enableDebugLogging {
            print("RelevaSDK: Sending \(method.rawValue) request to \(request.url?.absoluteString ?? "")")
            if let body = body {
                print("RelevaSDK: Request body: \(body)")
            }
        }

        // Outside the `do` above on purpose: the errors below are already `RelevaError`s with a
        // meaningful kind, and re-wrapping them as `.networkError` would flatten them.
        return try await executeRequest(request, retryAttempts: retryAttempts)
    }

    /// Execute URLRequest, retrying transport failures and 5xx responses.
    private func executeRequest(_ request: URLRequest, retryAttempts: Int) async throws -> Data {
        var attemptsLeft = retryAttempts

        while true {
            let retryDelayNanoseconds: UInt64

            do {
                return try await send(request)
            } catch let error as RelevaError {
                // Only 5xx is retried. `.unauthorized`, a 4xx `.serverError` and
                // `.invalidResponse` are all final, exactly as before.
                guard attemptsLeft > 0,
                      case .serverError(let statusCode, _) = error,
                      (500...599).contains(statusCode) else {
                    throw error
                }
                if config.enableDebugLogging {
                    print("RelevaSDK: Server error \(statusCode), retrying...")
                }
                retryDelayNanoseconds = 2_000_000_000
            } catch {
                guard attemptsLeft > 0 else {
                    throw RelevaError.networkError(error.localizedDescription)
                }
                if config.enableDebugLogging {
                    print("RelevaSDK: Request failed, retrying... (\(attemptsLeft) attempts left)")
                }
                retryDelayNanoseconds = 1_000_000_000
            }

            attemptsLeft -= 1
            try await Task.sleep(nanoseconds: retryDelayNanoseconds)
        }
    }

    /// One attempt: run the request and map the HTTP status onto `RelevaError`.
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelevaError.invalidResponse("No HTTP response")
        }

        if config.enableDebugLogging {
            print("RelevaSDK: Response status code: \(httpResponse.statusCode)")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw RelevaError.unauthorized
        default:
            throw RelevaError.serverError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
    }

    /// Build push request payload with context
    ///
    /// Internal (not private) so the identity-merge contract can be unit-tested via `@testable`.
    func buildPushPayload(request: [String: Any], context: [String: Any]) -> [String: Any] {
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

        // Merge request data into context. NOTE: `profile` is deliberately NOT mergeable from the
        // request — identity (`context.profile.id`) is owned by the context builder. No public API
        // can set request["profile"] anymore, so allowing it here would only risk re-introducing the
        // identity-clobber bug where a request profile map overwrote context.profile.id.
        if var contextCopy = payload["context"] as? [String: Any] {
            request.forEach { key, value in
                if key == "page" || key == "product" || key == "events" {
                    contextCopy[key] = value
                }
            }
            payload["context"] = contextCopy
        }

        return payload
    }
}

// MARK: - SDK Version

struct SDKVersion {
    static let current = "5.0.0"
}
