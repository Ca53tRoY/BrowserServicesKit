//
//  TunnelSettings.swift
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

import Combine
import Foundation

// swiftlint:disable type_body_length file_length

/// Persists and publishes changes to tunnel settings.
///
/// It's strongly recommended to use shared `UserDefaults` to initialize this class, as `TunnelSettingsUpdater`
/// can then detect settings changes using KVO even if they're applied by a different process or even by the user through
/// the command line.
///
public final class TunnelSettings {

    public enum Change: Codable {
        case setConnectOnLogin(_ connectOnLogin: Bool)
        case setIncludeAllNetworks(_ includeAllNetworks: Bool)
        case setEnforceRoutes(_ enforceRoutes: Bool)
        case setExcludeLocalNetworks(_ excludeLocalNetworks: Bool)
        case setNotifyStatusChanges(_ notifyStatusChanges: Bool)
        case setRegistrationKeyValidity(_ validity: RegistrationKeyValidity)
        case setSelectedServer(_ selectedServer: SelectedServer)
        case setSelectedLocation(_ selectedLocation: SelectedLocation)
        case setSelectedEnvironment(_ selectedEnvironment: SelectedEnvironment)
        case setShowInMenuBar(_ showInMenuBar: Bool)
        case setShowVPNSettings(_ showVPNSettings: Bool)
    }

    public enum RegistrationKeyValidity: Codable {
        case automatic
        case custom(_ timeInterval: TimeInterval)
    }

    public enum SelectedServer: Codable, Equatable {
        case automatic
        case endpoint(String)

        public var stringValue: String? {
            switch self {
            case .automatic: return nil
            case .endpoint(let endpoint): return endpoint
            }
        }
    }

    public enum SelectedLocation: Codable, Equatable {
        case nearest
        case location(NetworkProtectionSelectedLocation)

        public var location: NetworkProtectionSelectedLocation? {
            switch self {
            case .nearest: return nil
            case .location(let location): return location
            }
        }
    }

    public enum SelectedEnvironment: String, Codable {
        case production
        case staging

        public static var `default`: SelectedEnvironment = .production

        public var endpointURL: URL {
            switch self {
            case .production:
                return URL(string: "https://controller.netp.duckduckgo.com")!
            case .staging:
                return URL(string: "https://staging1.netp.duckduckgo.com")!
            }
        }
    }

    private let defaults: UserDefaults

    private(set) public lazy var changePublisher: AnyPublisher<Change, Never> = {

        let connectOnLoginPublisher = connectOnLoginPublisher.map { connectOnLogin in
            Change.setConnectOnLogin(connectOnLogin)
        }.eraseToAnyPublisher()

        let includeAllNetworksPublisher = includeAllNetworksPublisher.map { includeAllNetworks in
            Change.setIncludeAllNetworks(includeAllNetworks)
        }.eraseToAnyPublisher()

        let enforceRoutesPublisher = enforceRoutesPublisher.map { enforceRoutes in
            Change.setEnforceRoutes(enforceRoutes)
        }.eraseToAnyPublisher()

        let excludeLocalNetworksPublisher = excludeLocalNetworksPublisher.map { excludeLocalNetworks in
            Change.setExcludeLocalNetworks(excludeLocalNetworks)
        }.eraseToAnyPublisher()

        let notifyStatusChangesPublisher = notifyStatusChangesPublisher.map { notifyStatusChanges in
            Change.setNotifyStatusChanges(notifyStatusChanges)
        }.eraseToAnyPublisher()

        let registrationKeyValidityPublisher = registrationKeyValidityPublisher.map { validity in
            Change.setRegistrationKeyValidity(validity)
        }.eraseToAnyPublisher()

        let serverChangePublisher = selectedServerPublisher.map { server in
            Change.setSelectedServer(server)
        }.eraseToAnyPublisher()

        let locationChangePublisher = selectedLocationPublisher.map { location in
            Change.setSelectedLocation(location)
        }.eraseToAnyPublisher()

        let environmentChangePublisher = selectedEnvironmentPublisher.map { environment in
            Change.setSelectedEnvironment(environment)
        }.eraseToAnyPublisher()

        let showInMenuBarPublisher = showInMenuBarPublisher.map { showInMenuBar in
            Change.setShowInMenuBar(showInMenuBar)
        }.eraseToAnyPublisher()

        let showVPNSettingsPublisher = showVPNSettingsPublisher.map { showVPNSettings in
            Change.setShowVPNSettings(showVPNSettings)
        }.eraseToAnyPublisher()

        return Publishers.MergeMany(
            connectOnLoginPublisher,
            includeAllNetworksPublisher,
            enforceRoutesPublisher,
            excludeLocalNetworksPublisher,
            notifyStatusChangesPublisher,
            serverChangePublisher,
            locationChangePublisher,
            environmentChangePublisher,
            showInMenuBarPublisher,
            showVPNSettingsPublisher).eraseToAnyPublisher()
    }()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Resetting to Defaults

    public func resetToDefaults() {
        defaults.resetNetworkProtectionSettingConnectOnLogin()
        defaults.resetNetworkProtectionSettingEnforceRoutes()
        defaults.resetNetworkProtectionSettingExcludeLocalNetworks()
        defaults.resetNetworkProtectionSettingIncludeAllNetworks()
        defaults.resetNetworkProtectionSettingNotifyStatusChanges()
        defaults.resetNetworkProtectionSettingRegistrationKeyValidity()
        defaults.resetNetworkProtectionSettingSelectedServer()
        defaults.resetNetworkProtectionSettingSelectedEnvironment()
        defaults.resetNetworkProtectionSettingShowInMenuBar()
        defaults.resetNetworkProtectionSettingShowVPNSettings()
    }

    // MARK: - Applying Changes

    // swiftlint:disable:next cyclomatic_complexity
    public func apply(change: Change) {
        switch change {
        case .setConnectOnLogin(let connectOnLogin):
            self.connectOnLogin = connectOnLogin
        case .setEnforceRoutes(let enforceRoutes):
            self.enforceRoutes = enforceRoutes
        case .setExcludeLocalNetworks(let excludeLocalNetworks):
            self.excludeLocalNetworks = excludeLocalNetworks
        case .setIncludeAllNetworks(let includeAllNetworks):
            self.includeAllNetworks = includeAllNetworks
        case .setNotifyStatusChanges(let notifyStatusChanges):
            self.notifyStatusChanges = notifyStatusChanges
        case .setRegistrationKeyValidity(let registrationKeyValidity):
            self.registrationKeyValidity = registrationKeyValidity
        case .setSelectedServer(let selectedServer):
            self.selectedServer = selectedServer
        case .setSelectedLocation(let selectedLocation):
            self.selectedLocation = selectedLocation
        case .setSelectedEnvironment(let selectedEnvironment):
            self.selectedEnvironment = selectedEnvironment
        case .setShowInMenuBar(let showInMenuBar):
            self.showInMenuBar = showInMenuBar
        case .setShowVPNSettings(let showVPNSettings):
            self.showVPNSettings = showVPNSettings
        }
    }

    // MARK: - Connect on Login

    public var connectOnLoginPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingConnectOnLoginPublisher
    }

    public var connectOnLogin: Bool {
        get {
            defaults.networkProtectionSettingConnectOnLogin
        }

        set {
            defaults.networkProtectionSettingConnectOnLogin = newValue
        }
    }

    // MARK: - Enforce Routes

    public var includeAllNetworksPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingIncludeAllNetworksPublisher
    }

    public var includeAllNetworks: Bool {
        get {
            defaults.networkProtectionSettingIncludeAllNetworks
        }

        set {
            defaults.networkProtectionSettingIncludeAllNetworks = newValue
        }
    }

    // MARK: - Enforce Routes

    public var enforceRoutesPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingEnforceRoutesPublisher
    }

    public var enforceRoutes: Bool {
        get {
            defaults.networkProtectionSettingEnforceRoutes
        }

        set {
            defaults.networkProtectionSettingEnforceRoutes = newValue
        }
    }

    // MARK: - Exclude Local Routes

    public var excludeLocalNetworksPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingExcludeLocalNetworksPublisher
    }

    public var excludeLocalNetworks: Bool {
        get {
            defaults.networkProtectionSettingExcludeLocalNetworks
        }

        set {
            defaults.networkProtectionSettingExcludeLocalNetworks = newValue
        }
    }

    // MARK: - Registration Key Validity

    public var registrationKeyValidityPublisher: AnyPublisher<RegistrationKeyValidity, Never> {
        defaults.networkProtectionSettingRegistrationKeyValidityPublisher
    }

    public var registrationKeyValidity: RegistrationKeyValidity {
        get {
            defaults.networkProtectionSettingRegistrationKeyValidity
        }

        set {
            defaults.networkProtectionSettingRegistrationKeyValidity = newValue
        }
    }

    private var networkProtectionSettingRegistrationKeyValidityDefault: TimeInterval {
        .days(2)
    }

    // MARK: - Server Selection

    public var selectedServerPublisher: AnyPublisher<SelectedServer, Never> {
        defaults.networkProtectionSettingSelectedServerPublisher
    }

    public var selectedServer: SelectedServer {
        get {
            defaults.networkProtectionSettingSelectedServer
        }

        set {
            defaults.networkProtectionSettingSelectedServer = newValue
        }
    }

    // MARK: - Location Selection

    public var selectedLocationPublisher: AnyPublisher<SelectedLocation, Never> {
        defaults.networkProtectionSettingSelectedLocationPublisher
    }

    public var selectedLocation: SelectedLocation {
        get {
            defaults.networkProtectionSettingSelectedLocation
        }

        set {
            defaults.networkProtectionSettingSelectedLocation = newValue
        }
    }

    // MARK: - Environment

    public var selectedEnvironmentPublisher: AnyPublisher<SelectedEnvironment, Never> {
        defaults.networkProtectionSettingSelectedEnvironmentPublisher
    }

    public var selectedEnvironment: SelectedEnvironment {
        get {
            defaults.networkProtectionSettingSelectedEnvironment
        }

        set {
            defaults.networkProtectionSettingSelectedEnvironment = newValue
        }
    }

    // MARK: - Show in Menu Bar

    public var showInMenuBarPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingShowInMenuBarPublisher
    }

    public var showInMenuBar: Bool {
        get {
            defaults.networkProtectionSettingShowInMenuBar
        }

        set {
            defaults.networkProtectionSettingShowInMenuBar = newValue
        }
    }

    // MARK: - Show VPN Settings

    public var showVPNSettingsPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionSettingShowVPNSettingsPublisher
    }

    public var showVPNSettings: Bool {
        get {
            defaults.networkProtectionSettingShowVPNSettings
        }

        set {
            defaults.networkProtectionSettingShowVPNSettings = newValue
        }
    }

    // MARK: - Notify Status Changes

    public var notifyStatusChangesPublisher: AnyPublisher<Bool, Never> {
        defaults.networkProtectionNotifyStatusChangesPublisher
    }

    public var notifyStatusChanges: Bool {
        get {
            defaults.networkProtectionNotifyStatusChanges
        }

        set {
            defaults.networkProtectionNotifyStatusChanges = newValue
        }
    }

    // MARK: - Routes

    public enum ExclusionListItem {
        case section(String)
        case exclusion(range: NetworkProtection.IPAddressRange, description: String? = nil, `default`: Bool)
    }

    public let exclusionList: [ExclusionListItem] = [
        .section("IPv4 Local Routes"),

        .exclusion(range: "10.0.0.0/8"     /* 255.0.0.0 */, description: "disabled for enforceRoutes", default: true),
        .exclusion(range: "172.16.0.0/12"  /* 255.240.0.0 */, default: true),
        .exclusion(range: "192.168.0.0/16" /* 255.255.0.0 */, default: true),
        .exclusion(range: "169.254.0.0/16" /* 255.255.0.0 */, description: "Link-local", default: true),
        .exclusion(range: "127.0.0.0/8"    /* 255.0.0.0 */, description: "Loopback", default: true),
        .exclusion(range: "224.0.0.0/4"    /* 240.0.0.0 (corrected subnet mask) */, description: "Multicast", default: true),
        .exclusion(range: "100.64.0.0/16"  /* 255.255.0.0 */, description: "Shared Address Space", default: true),

        .section("IPv6 Local Routes"),
        .exclusion(range: "fe80::/10", description: "link local", default: false),
        .exclusion(range: "ff00::/8", description: "multicast", default: false),
        .exclusion(range: "fc00::/7", description: "local unicast", default: false),
        .exclusion(range: "::1/128", description: "loopback", default: false),

        .section("duckduckgo.com"),
        .exclusion(range: "52.142.124.215/32", default: false),
        .exclusion(range: "52.250.42.157/32", default: false),
        .exclusion(range: "40.114.177.156/32", default: false),
    ]
}

// swiftlint:enable type_body_length file_length
