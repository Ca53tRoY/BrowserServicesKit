//
//  AuthServiceRequest.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import os.log

/// Auth API v2 Endpoints: https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md#auth-api-v2-endpoints
struct OAuthRequest {

    let apiRequest: APIRequestV2
    let httpSuccessCode: HTTPStatusCode
    let httpErrorCodes: [HTTPStatusCode]
    static let errorDetails = [
        "invalid_authorization_request": "One or more of the required parameters are missing or any provided parameters have invalid values",
        "authorize_failed": "Failed to create the authorization session, either because of a reused code challenge or internal server error",
        "invalid_request": "The ddg_auth_session_id is missing or has already been used to log in to a different account",
        "account_create_failed": "Failed to create the account because of an internal server error",
        "invalid_email_address": "Provided email address is missing or of an invalid format",
        "invalid_session_id": "The session id is missing, invalid or has already been used for logging in",
        "suspended_account": "The account you are logging in to is suspended",
        "email_sending_error": "Failed to send the OTP to the email address provided",
        "invalid_login_credentials": "One or more of the provided parameters is invalid",
        "unknown_account": "The login credentials appear valid but do not link to a known account",
        "invalid_token_request": "One or more of the required parameters are missing or any provided parameters have invalid values",
        "unverified_account": "The token is valid but is for an unverified account",
        "email_address_not_changed": "New email address is the same as the old email address",
        "failed_mx_check": "DNS check to see if email address domain is valid failed",
        "account_edit_failed": "Something went wrong and the edit was aborted",
        "invalid_link_signature": "The hash is invalid or does not match the provided email address and account",
        "account_change_email_address_failed": "Something went wrong and the edit was aborted",
        "invalid_token": "Provided access token is missing or invalid",
        "expired_token": "Provided access token is expired"
    ]

    struct BodyError: Decodable {
        let error: String
    }

    internal init(apiRequest: APIRequestV2,
                  httpSuccessCode: HTTPStatusCode = HTTPStatusCode.ok,
                  httpErrorCodes: [HTTPStatusCode] = [HTTPStatusCode.badRequest, HTTPStatusCode.internalServerError]) {
        self.apiRequest = apiRequest
        self.httpSuccessCode = httpSuccessCode
        self.httpErrorCodes = httpErrorCodes
    }

    // MARK: Authorize

    static func authorize(baseURL: URL, codeChallenge: String) -> OAuthRequest? {
        let path = "/api/auth/v2/authorize"
        let queryItems = [
            "response_type": "code",
            "code_challenge": codeChallenge,
            "code_challenge_method": "S256",
            "client_id": "f4311287-0121-40e6-8bbd-85c36daf1837",
            "redirect_uri": "com.duckduckgo:/authcb",
            "scope": "privacypro"
        ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpSuccessCode: HTTPStatusCode.found)
    }

    // MARK: Create account

    static func createAccount(baseURL: URL, authSessionID: String) -> OAuthRequest? {
        let path = "/api/auth/v2/account/create"
        let headers = [ HTTPHeaderKey.cookie: authSessionID ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         headers: APIRequestV2.HeadersV2(additionalHeaders: headers)) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpSuccessCode: HTTPStatusCode.found)
    }

    // MARK: Sent OTP

    static func sendOTP(baseURL: URL, authSessionID: String, emailAddress: String) -> OAuthRequest? {
        let path = "/api/auth/v2/otp"
        let headers = [ HTTPHeaderKey.cookie: authSessionID ]
        let queryItems = [ "email": emailAddress ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         queryItems: queryItems,
                                         headers: APIRequestV2.HeadersV2(additionalHeaders: headers)) else {
            return nil
        }
        return OAuthRequest(apiRequest: request)
    }

    // MARK: Login

    static func login(baseURL: URL, authSessionID: String, method: OAuthLoginMethod) -> OAuthRequest? {
        let path = "/api/auth/v2/login"
        let headers = [ HTTPHeaderKey.cookie: authSessionID ]
        var queryItems: [String: String]
        switch method.self {
        case is OAuthLoginMethodOTP:
            guard let otpMethod = method as? OAuthLoginMethodOTP else {
                return nil
            }
            queryItems = [
                "method": otpMethod.name,
                "email": otpMethod.email,
                "otp": otpMethod.otp
            ]
        case is OAuthLoginMethodSignature:
            guard let signatureMethod = method as? OAuthLoginMethodSignature else {
                return nil
            }
            queryItems = [
                "method": signatureMethod.name,
                "email": signatureMethod.signature,
                "source": signatureMethod.source
            ]
        default:
            Logger.networking.fault("Unknown login method: \(String(describing: method))")
            return nil
        }

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         queryItems: queryItems,
                                         headers: APIRequestV2.HeadersV2(additionalHeaders: headers)) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpSuccessCode: HTTPStatusCode.found)
    }

    // MARK: Access Token
    // Note: The API has a single endpoint for both getting a new token and refreshing an old one, but here I'll split the endpoint in 2 different calls
    // https://dub.duckduckgo.com/duckduckgo/ddg/blob/main/components/auth/docs/AuthAPIV2Documentation.md#access-token

    static func getAccessToken(baseURL: URL, clientID: String, codeVerifier: String, code: String, redirectURI: String) -> OAuthRequest? {
        let path = "/api/auth/v2/token"
        let queryItems = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code_verifier": codeVerifier,
            "code": code,
            "redirect_uri": redirectURI
        ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems) else {
            return nil
        }

        return OAuthRequest(apiRequest: request)
    }

    static func refreshAccessToken(baseURL: URL, clientID: String, refreshToken: String) -> OAuthRequest? {
        let path = "/api/auth/v2/token"
        let queryItems = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ]
        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems) else {
            return nil
        }
        return OAuthRequest(apiRequest: request)
    }

    // MARK: Edit Account

    static func editAccount(baseURL: URL, accessToken: String, email: String?) -> OAuthRequest? {
        let path = "/api/auth/v2/account/edit"
        let headers = [
            HTTPHeaderKey.authorization: "Bearer \(accessToken)"
        ]
        var queryItems: [String: String] = [:]

        if let email {
            queryItems["email"] = email
        }

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         queryItems: queryItems,
                                         headers: APIRequestV2.HeadersV2(additionalHeaders: headers)) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpErrorCodes: [.unauthorized, .internalServerError])
    }

    static func confirmEditAccount(baseURL: URL, accessToken: String, email: String, hash: String, otp: String) -> OAuthRequest? {
        let path = "/account/edit/confirm"
        let headers = [
            HTTPHeaderKey.authorization: "Bearer \(accessToken)"
        ]
        let queryItems = [
            "email": email,
            "hash": hash,
            "otp": otp,
        ]

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .get,
                                         queryItems: queryItems,
                                         headers: APIRequestV2.HeadersV2(additionalHeaders: headers)) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpErrorCodes: [.unauthorized, .internalServerError])
    }

    // MARK: Logout

    static func logout(baseURL: URL, accessToken: String) -> OAuthRequest? {
        let path = "/api/auth/v2/logout"
        let headers = [
            HTTPHeaderKey.authorization: "Bearer \(accessToken)"
        ]

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         headers: APIRequestV2.HeadersV2(additionalHeaders: headers)) else {
            return nil
        }
        return OAuthRequest(apiRequest: request, httpErrorCodes: [.unauthorized, .internalServerError])
    }

    // MARK: Exchange token

    static func exchangeToken(baseURL: URL, accessTokenV1: String, authSessionID: String) -> OAuthRequest? {
        let path = "/api/auth/v2/exchange"
        let headers = [
            HTTPHeaderKey.authorization: "Bearer \(accessTokenV1)",
            HTTPHeaderKey.cookie: authSessionID
        ]

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path),
                                         method: .post,
                                         headers: APIRequestV2.HeadersV2(additionalHeaders: headers)) else {
            return nil
        }
        return OAuthRequest(apiRequest: request,
                            httpSuccessCode: .found,
                            httpErrorCodes: [.unauthorized, .internalServerError])
    }

    // MARK: JWKs

    /// This endpoint is where the Auth service will publish public keys for consuming services and clients to use to independently verify access tokens. Tokens should be downloaded and cached for an hour upon first use. When rotating private keys for signing JWTs, the Auth service will publish new public keys 24 hours in advance of starting to sign new JWTs with them. This should provide consuming services with plenty of time to invalidate their public key cache and have the new key available before they can expect to start receiving JWTs signed with the old key. The old key will remain published until the next key rotation, so there should generally be two public keys available through this endpoint. The response format is a standard JWKS response, as documented in RFC 7517.
    static func jwks(baseURL: URL) -> OAuthRequest? {
        let path = "/api/auth/v2/.well-known/jwks.json"

        guard let request = APIRequestV2(url: baseURL.appendingPathComponent(path), method: .get) else {
            return nil
        }
        return OAuthRequest(apiRequest: request,
                            httpSuccessCode: .ok,
                            httpErrorCodes: [.internalServerError])
    }
}