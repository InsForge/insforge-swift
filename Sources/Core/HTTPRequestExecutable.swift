import Foundation

// MARK: - executeRequest

/// Shared helper for executing HTTP requests with optional automatic token refresh.
///
/// This is an internal implementation detail of the InsForge SDK and is not
/// part of the public API surface.
public func executeRequest(
    _ method: HTTPMethod,
    url: URL,
    headers: [String: String],
    body: Data? = nil,
    httpClient: HTTPClient,
    tokenRefreshHandler: (any TokenRefreshHandler)?
) async throws -> HTTPResponse {
    if let handler = tokenRefreshHandler {
        return try await httpClient.executeWithAutoRefresh(
            method,
            url: url,
            headers: headers,
            body: body,
            refreshHandler: handler
        )
    } else {
        return try await httpClient.execute(
            method,
            url: url,
            headers: headers,
            body: body
        )
    }
}
