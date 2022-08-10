//
//  AdClickAttributionFeatureTests.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import XCTest
import BrowserServicesKit

class AdClickAttributionFeatureTests: XCTestCase {
    
    let exampleConfig = """
{
    "readme": "https://github.com/duckduckgo/privacy-configuration",
    "version": 1655387185511,
    "features": {
        "adClickAttribution": {
                    "readme": "https://duckduckgo.com/path/to/readme",
                    "exceptions": [],
                    "settings": {
                        "linkFormats": [
                          {
                            "url": "good.first-party.site/y.js",
                            "parameterName": "u3",
                            "adDomainParameterName": "test_param",
                            "desc": "Test Domain"
                          },
                          {
                            "url": "good.first-party.example/y.js",
                            "parameterName": "u3",
                            "desc": "Test Domain"
                          },
                          {
                            "url": "other.first-party.com/m.js",
                            "parameterName": "dsl",
                            "parameterValue": "1",
                            "desc": "Shopping Ads"
                          }
                        ],
                        "allowlist": [
                            { "blocklistEntry": "bing.com", "host": "bat.bing.com" },
                            { "blocklistEntry": "ad-site.site", "host": "conversion.ad-site.site" },
                            { "blocklistEntry": "ad-site.example", "host": "conversion.ad-site.example" }
                         ],
                        "navigationExpiration": 1800,
                        "totalExpiration": 604800
                    },
                    "state": "enabled"
        }
    },
    "unprotectedTemporary": [
    ]
}
""".data(using: .utf8)!
    
    
    func testDomainMatching() {

        let dataProvider = MockEmbeddedDataProvider(data: exampleConfig, etag: "empty")
        
        let config = PrivacyConfigurationManager(fetchedETag: nil,
                                                 fetchedData: nil,
                                                 embeddedDataProvider: dataProvider,
                                                 localProtection: MockDomainsProtectionStore())
        
        let feature = AdClickAttributionFeature(with: config)
        
        XCTAssertTrue(feature.isEnabled)

        XCTAssertEqual(Set(feature.allowlist.map { $0.entity }), Set(["bing.com", "ad-site.site", "ad-site.example"]))
        
        XCTAssertTrue(feature.isMatchingAttributionFormat(URL(string: "https://good.first-party.site/y.js?u3=1")!))
        XCTAssertTrue(feature.isMatchingAttributionFormat(URL(string: "https://good.first-party.site/y.js?u3=test")!))
        XCTAssertTrue(feature.isMatchingAttributionFormat(URL(string: "https://good.first-party.site/y.js?test_param=test")!))
        
        XCTAssertFalse(feature.isMatchingAttributionFormat(URL(string: "https://good.first-party.site/y.js")!))
        XCTAssertFalse(feature.isMatchingAttributionFormat(URL(string: "https://good.first-party.site/y.js?u2=2")!))
        XCTAssertFalse(feature.isMatchingAttributionFormat(URL(string: "https://good.first-party.site/y.js.gif?u2=2")!))
        XCTAssertFalse(feature.isMatchingAttributionFormat(URL(string: "https://sub.good.first-party.site/y.js?u3=2")!))
        
        XCTAssertTrue(feature.isMatchingAttributionFormat(URL(string: "https://good.first-party.example/y.js?u3=1")!))
        XCTAssertTrue(feature.isMatchingAttributionFormat(URL(string: "https://good.first-party.example/y.js?u3=test")!))
        XCTAssertFalse(feature.isMatchingAttributionFormat(URL(string: "https://good.first-party.example/y.js?test_param=test.com")!))
        
        XCTAssertTrue(feature.isMatchingAttributionFormat(URL(string: "https://other.first-party.com/m.js?dsl=1")!))
        XCTAssertFalse(feature.isMatchingAttributionFormat(URL(string: "https://other.first-party.com/m.js?dsl=2")!))
        XCTAssertFalse(feature.isMatchingAttributionFormat(URL(string: "https://other.first-party.com/m.js?ad_domain=a.com")!))
        XCTAssertFalse(feature.isMatchingAttributionFormat(URL(string: "https://other.first-party.com/m.js?test_param=test.com")!))
    }
}