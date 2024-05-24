import Foundation
import PhishingDetection

public class MockPhishingDetectionClient: PhishingDetectionClientProtocol {
    private var filterRevisions: [Int: FilterSetResponse] = [
        0: FilterSetResponse(insert: [
            Filter(hashValue: "testhash1", regex: ".*example.*"),
            Filter(hashValue: "testhash2", regex: ".*test.*")
        ], delete: [], revision: 0, replace: true),
        1: FilterSetResponse(insert: [
            Filter(hashValue: "testhash3", regex: ".*test.*")
        ], delete: [
            Filter(hashValue: "testhash1", regex: ".*example.*"),
        ], revision: 1, replace: false),
        2: FilterSetResponse(insert: [
            Filter(hashValue: "testhash4", regex: ".*test.*")
        ], delete: [
            Filter(hashValue: "testhash2", regex: ".*test.*"),
        ], revision: 2, replace: false),
        4: FilterSetResponse(insert: [
            Filter(hashValue: "testhash5", regex: ".*test.*")
        ], delete: [
            Filter(hashValue: "testhash3", regex: ".*test.*"),
        ], revision: 4, replace: false)
    ]

    private var hashPrefixRevisions: [Int: HashPrefixResponse] = [
        0: HashPrefixResponse(insert: [
            "aa00bb11",
            "bb00cc11",
            "cc00dd11",
            "dd00ee11",
            "a379a6f6"
        ], delete: [], revision: 0, replace: true),
        1: HashPrefixResponse(insert: ["93e2435e"], delete: [
            "cc00dd11",
            "dd00ee11",
        ], revision: 1, replace: false),
        2: HashPrefixResponse(insert: ["c0be0d0a6"], delete: [
            "bb00cc11",
        ], revision: 2, replace: false),
        4: HashPrefixResponse(insert: ["a379a6f6"], delete: [
            "aa00bb11",
        ], revision: 4, replace: false)
    ]

    public func getFilterSet(revision: Int) async -> FilterSetResponse {
        return filterRevisions[revision] ?? FilterSetResponse(insert: [], delete: [], revision: revision, replace: false)
    }

    public func getHashPrefixes(revision: Int) async -> HashPrefixResponse {
        return hashPrefixRevisions[revision] ?? HashPrefixResponse(insert: [], delete: [], revision: revision, replace: false)
    }

    public func getMatches(hashPrefix: String) async -> [Match] {
        return [
            Match(hostname: "example.com", url: "https://example.com/mal", regex: ".", hash: "a379a6f6eeafb9a55e378c118034e2751e682fab9f2d30ab13d2125586ce1947"),
            Match(hostname: "test.com", url: "https://test.com/mal", regex: ".*test.*", hash: "aa00bb11aa00cc11bb00cc11")
        ]
    }
}
