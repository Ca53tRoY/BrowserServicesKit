
import Foundation
import BrowserServicesKit

struct UpdatesSender: UpdatesSending {

    var offlineUpdatesFile: URL {
        fileStorageUrl.appendingPathComponent("offline-updates.json")
    }

    let fileStorageUrl: URL
    let persistence: LocalDataPersisting
    let dependencies: SyncDependencies

    private(set) var bookmarks = [BookmarkUpdate]()

    func persistingBookmark(_ bookmark: SavedSiteItem) throws -> UpdatesSending {
        return try appendBookmark(bookmark, deleted: false)
    }

    func persistingBookmarkFolder(_ folder: SavedSiteFolder) throws -> UpdatesSending {
        return try appendFolder(folder, deleted: false)
    }

    func deletingBookmark(_ bookmark: SavedSiteItem) throws -> UpdatesSending {
        return try appendBookmark(bookmark, deleted: true)
    }

    func deletingBookmarkFolder(_ folder: SavedSiteFolder) throws -> UpdatesSending {
        return try appendFolder(folder, deleted: true)
    }

    private func appendBookmark(_ bookmark: SavedSiteItem, deleted: Bool) throws -> UpdatesSender {
        let encryptedTitle = try dependencies.crypter.encryptAndBase64Encode(bookmark.title)
        let encryptedUrl = try dependencies.crypter.encryptAndBase64Encode(bookmark.url)
        let update = BookmarkUpdate(id: bookmark.id,
                                    next: bookmark.nextItem,
                                    parent: bookmark.parent,
                                    title: encryptedTitle,
                                    page: .init(url: encryptedUrl),
                                    favorite: bookmark.isFavorite ? .init(next: bookmark.nextFavorite) : nil,
                                    folder: nil,
                                    deleted: deleted ? "" : nil)
        
        return UpdatesSender(fileStorageUrl: fileStorageUrl,
                             persistence: persistence,
                             dependencies: dependencies,
                             bookmarks: bookmarks + [update])
    }
    
    private func appendFolder(_ folder: SavedSiteFolder, deleted: Bool) throws -> UpdatesSender {
        let encryptedTitle = try dependencies.crypter.encryptAndBase64Encode(folder.title)
        let update = BookmarkUpdate(id: folder.id,
                                    next: folder.nextItem,
                                    parent: folder.parent,
                                    title: encryptedTitle,
                                    page: nil,
                                    favorite: nil,
                                    folder: .init(),
                                    deleted: deleted ? "" : nil)
        
        return UpdatesSender(fileStorageUrl: fileStorageUrl,
                             persistence: persistence,
                             dependencies: dependencies,
                             bookmarks: bookmarks + [update])
    }

    func send() async throws {
        guard let account = try dependencies.secureStore.account() else { throw SyncError.accountNotFound }
        guard let token = account.token else { throw SyncError.noToken }
 
        let updates = prepareUpdates()
        let syncUrl = dependencies.endpoints.syncPatch
    
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(updates)

        switch try await send(jsonData, withAuthorization: token, toUrl: syncUrl) {
        case .success(let updates):
            if !updates.isEmpty {
                do {
                    try await dependencies.responseHandler.handleUpdates(updates)
                } catch {
                    throw error
                }
            }
            try removeOfflineFile()

        case .failure(let error):
            switch error {
            case SyncError.unexpectedStatusCode(let statusCode):
                if statusCode == 403 {
                    try dependencies.secureStore.removeAccount()
                    try removeOfflineFile()
                    throw SyncError.accountRemoved
                }
                
            default: break
            }
            
            // Save updates for later unless this was a 403
            try saveForLater(updates)
        }
    }
    
    private func prepareUpdates() -> Updates {
        if var updates = loadPreviouslyFailedUpdates() {
            updates.bookmarks.modified_since = persistence.bookmarksLastModified
            updates.bookmarks.updates += self.bookmarks
            return updates
        }
        return Updates(bookmarks: BookmarkUpdates(modified_since: persistence.bookmarksLastModified, updates: bookmarks))
    }
  
    private func loadPreviouslyFailedUpdates() -> Updates? {
        guard let data = try? Data(contentsOf: offlineUpdatesFile) else { return nil }
        return try? JSONDecoder().decode(Updates.self, from: data)
    }
    
    private func saveForLater(_ updates: Updates) throws {
        try JSONEncoder().encode(updates).write(to: offlineUpdatesFile, options: .atomic)
    }
    
    private func removeOfflineFile() throws {
        if (try? offlineUpdatesFile.checkResourceIsReachable()) == true {
            try FileManager.default.removeItem(at: offlineUpdatesFile)
        }
    }
    
    private func send(_ json: Data, withAuthorization authorization: String, toUrl url: URL) async throws -> Result<Data, Error> {
        
        var request = dependencies.api.createRequest(url: url, method: .PATCH)
        request.addHeader("Authorization", value: "bearer \(authorization)")
        request.setBody(body: json, withContentType: "application/json")
        let result = try await request.execute()
        guard (200 ..< 300).contains(result.response.statusCode) else {
            throw SyncError.unexpectedStatusCode(result.response.statusCode)
        }

        guard let data = result.data else {
            throw SyncError.noResponseBody
        }

        return .success(data)
    }

    struct Updates: Codable {

        var bookmarks: BookmarkUpdates
        
    }
    
    struct BookmarkUpdates: Codable {
        
        var modified_since: String?
        var updates: [BookmarkUpdate]
        
    }
    
}