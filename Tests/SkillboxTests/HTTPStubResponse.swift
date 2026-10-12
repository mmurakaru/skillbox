import Foundation

enum HTTPStubError: Error {
    case missingRequestURL
    case missingHandler
}

/// Builds the response a URL protocol stub returns for a request, failing the test instead of crashing it.
func stubHTTPResponse(for request: URLRequest, status: Int = 200) throws -> HTTPURLResponse {
    guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
        throw HTTPStubError.missingRequestURL
    }

    return response
}
