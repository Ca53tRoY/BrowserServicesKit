//
//  APIService.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Common

public enum APIServiceError: Swift.Error {
    case decodingError
    case encodingError
    case serverError(description: String)
    case unknownServerError
    case connectionError
}

struct ErrorResponse: Decodable {
    let error: String
}

public protocol APIService {
    static var baseURL: URL { get }
    static var session: URLSession { get }
    static func executeAPICall<T>(method: String, endpoint: String, headers: [String: String]?, body: Data?, queryParameters: [String: String]?) async -> Result<T, APIServiceError> where T: Decodable
}

public extension APIService {

    static func executeAPICall<T>(method: String, endpoint: String, headers: [String: String]? = nil, body: Data? = nil, queryParameters: [String: String]? = nil) async -> Result<T, APIServiceError> where T: Decodable {
        let request = makeAPIRequest(method: method, endpoint: endpoint, headers: headers, body: body, queryParameters: queryParameters)

        do {
            let (data, urlResponse) = try await session.data(for: request)

            printDebugInfo(method: method, endpoint: endpoint, data: data, response: urlResponse)

            if let httpResponse = urlResponse as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) {
                if let decodedResponse = decode(T.self, from: data) {
                    return .success(decodedResponse)
                } else {
                    os_log(.error, log: .phishingDetection, "Service error: APIServiceError.decodingError")
                    return .failure(.decodingError)
                }
            } else {
                if let decodedResponse = decode(ErrorResponse.self, from: data) {
                    let errorDescription = "[\(endpoint)] \(urlResponse.httpStatusCodeAsString ?? ""): \(decodedResponse.error)"
                    os_log(.error, log: .phishingDetection, "Service error: %{public}@", errorDescription)
                    return .failure(.serverError(description: errorDescription))
                } else {
                    if let string = String(data: data, encoding: .utf8) {
                        print(string)
                    } else {
                        print("Unable to convert data to text")
                    }
                    os_log(.error, log: .phishingDetection, "Service error: APIServiceError.unknownServerError")
                    return .failure(.unknownServerError)
                }
            }
        } catch {
            os_log(.error, log: .phishingDetection, "Service error: %{public}@", error.localizedDescription)
            return .failure(.connectionError)
        }
    }

    private static func makeAPIRequest(method: String, endpoint: String, headers: [String: String]?, body: Data?, queryParameters: [String: String]?) -> URLRequest {
        var urlComponents = URLComponents(string: baseURL.appendingPathComponent(endpoint).absoluteString)
        
        if let queryParameters = queryParameters {
            urlComponents?.queryItems = queryParameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let url = urlComponents?.url else {
            fatalError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        if let headers = headers {
            request.allHTTPHeaderFields = headers
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        return request
    }

    private static func decode<T>(_: T.Type, from data: Data) -> T? where T: Decodable {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .millisecondsSince1970

        return try? decoder.decode(T.self, from: data)
    }

    private static func printDebugInfo(method: String, endpoint: String, data: Data, response: URLResponse) {
        let statusCode = (response as? HTTPURLResponse)!.statusCode
        let stringData = String(data: data, encoding: .utf8) ?? ""

        os_log(.info, log: .phishingDetection, "[API] %d %{public}s /%{public}s :: %{public}s", statusCode, method, endpoint, stringData)
    }
}

extension URLResponse {

    var httpStatusCodeAsString: String? {
        guard let httpStatusCode = (self as? HTTPURLResponse)?.statusCode else { return nil }
        return String(httpStatusCode)
    }
}

public protocol PhishingDetectionAPIServiceProtocol {
    func updateFilterSet(revision: Int) async -> [Filter]
    func updateHashPrefixes(revision: Int) async -> [String]
    func getMatches(hashPrefix: String) async -> [Match]
}

public class PhishingDetectionAPIService: APIService, PhishingDetectionAPIServiceProtocol {
    
    public static let baseURL: URL = URL(string: "http://localhost:3000")!
    public static let session: URLSession = .shared
    var headers: [String: String]? = [:]
    
    public func updateFilterSet(revision: Int) async -> [Filter] {
        var endpoint = "filterSet"
        if revision > 0 {
            endpoint += "?revision=\(revision)"
        }
        let result: Result<FilterSetResponse, APIServiceError> = await Self.executeAPICall(method: "GET", endpoint: endpoint, headers: headers, body: nil)
        switch result {
        case .success(let filterSetResponse):
            return filterSetResponse.filters
        case .failure(let error):
            print("Failed to load: \(error)")
        }
        return []
    }
    
    public func updateHashPrefixes(revision: Int) async -> [String] {
        var endpoint = "hashPrefix"
        if revision > 0 {
            endpoint += "?revision=\(revision)"
        }
        let result: Result<HashPrefixResponse, APIServiceError> = await Self.executeAPICall(method: "GET", endpoint: endpoint, headers: headers, body: nil)
        
        switch result {
        case .success(let filterSetResponse):
            return filterSetResponse.hashPrefixes
        case .failure(let error):
            print("Failed to load: \(error)")
        }
        return []
    }
    
    public func getMatches(hashPrefix: String) async -> [Match] {
        let endpoint = "matches"
        let queryParams = ["hashPrefix": hashPrefix]
        let result: Result<MatchResponse, APIServiceError> = await Self.executeAPICall(method: "GET", endpoint: endpoint, headers: headers, body: nil, queryParameters: queryParams)
        
        switch result {
        case .success(let matchResponse):
            return matchResponse.matches
        case .failure(let error):
            print("Failed to load: \(error)")
            return []
        }
    }
    
}
