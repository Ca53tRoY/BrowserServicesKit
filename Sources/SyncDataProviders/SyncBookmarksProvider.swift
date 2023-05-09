//
//  SyncBookmarksProvider.swift
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
import Bookmarks
import CoreData
import Persistence
import DDGSync

public final class SyncBookmarksProvider: DataProviding {

    public let feature: Feature = .init(name: "bookmarks")

    public var lastSyncTimestamp: String? {
        get {
            metadataStore.timestamp(forFeatureNamed: feature.name)
        }
        set {
            metadataStore.updateTimestamp(newValue, forFeatureNamed: feature.name)
        }
    }

    public init(database: CoreDataDatabase, metadataStore: SyncMetadataStore, reloadBookmarksAfterSync: @escaping () -> Void) {
        self.database = database
        self.metadataStore = metadataStore
        self.metadataStore.registerFeature(named: feature.name)
        self.reloadBookmarksAfterSync = reloadBookmarksAfterSync
    }

    public func prepareForFirstSync() {
        lastSyncTimestamp = nil
    }

    public func fetchAllObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        return await withCheckedContinuation { continuation in
            var syncableBookmarks: [Syncable] = []

            let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

            context.performAndWait {
                let fetchRequest = BookmarkEntity.fetchRequest()
                let bookmarks = (try? context.fetch(fetchRequest)) ?? []
                syncableBookmarks = bookmarks.compactMap { try? Syncable(bookmark: $0, encryptedWith: crypter) }
            }
            continuation.resume(with: .success(syncableBookmarks))
        }
    }

    public func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        return await withCheckedContinuation { continuation in

            let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

            var syncableBookmarks: [Syncable] = []
            context.performAndWait {
                let bookmarks = BookmarkUtils.fetchModifiedBookmarks(context)
                syncableBookmarks = bookmarks.compactMap { try? Syncable(bookmark: $0, encryptedWith: crypter) }
            }
            continuation.resume(with: .success(syncableBookmarks))
        }
    }

    public func handleSyncResult(sent: [Syncable], received: [Syncable], timestamp: String?, crypter: Crypting) async {
        await withCheckedContinuation { continuation in
            var saveError: Error?

            let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

            context.performAndWait {
                cleanUpSentItems(sent, in: context)
                processReceivedBookmarks(received, in: context, using: crypter)

                let insertedObjects = Array(context.insertedObjects).compactMap { $0 as? BookmarkEntity }
                let updatedObjects = Array(context.updatedObjects.subtracting(context.deletedObjects)).compactMap { $0 as? BookmarkEntity }

                do {
                    try context.save()
                    (insertedObjects + updatedObjects).forEach { $0.modifiedAt = nil }
                    try context.save()
                } catch {
                    saveError = error
                }
            }
            if let saveError {
                print("SAVE ERROR", saveError)
            } else if let timestamp {
                lastSyncTimestamp = timestamp
                reloadBookmarksAfterSync()
            }

            continuation.resume()
        }
    }

    func cleanUpSentItems(_ sent: [Syncable], in context: NSManagedObjectContext) {
        if sent.isEmpty {
            return
        }
        let identifiers = sent.compactMap(\.uuid)
        let bookmarks = BookmarkEntity.fetchBookmarks(with: identifiers, in: context)
        for bookmark in bookmarks {
            if bookmark.isPendingDeletion {
                context.delete(bookmark)
            } else {
                bookmark.modifiedAt = nil
            }
        }
    }

    func processReceivedBookmarks(_ received: [Syncable], in context: NSManagedObjectContext, using crypter: Crypting) {
        if received.isEmpty {
            return
        }

        var metadata = ReceivedBookmarksMetadata(received: received)

        // index local bookmarks by UUID
        // update existing local bookmarks data and store them in processedUUIDs
        processExistingEntities(metadata: &metadata, in: context, using: crypter)

        // deduplication

        let topLevelFoldersSyncables: [Syncable] = {
            if let rootFolderSyncable = metadata.receivedByUUID[BookmarkEntity.Constants.rootFolderID] {
                return [rootFolderSyncable]
            }
            return metadata.foldersWithoutParent.compactMap { metadata.receivedByUUID[$0] }
        }()

        for topLevelFolderSyncable in topLevelFoldersSyncables {
            processTopLevelFolder(topLevelFolderSyncable, metadata: &metadata, in: context, using: crypter)
        }

        // at this point all new bookmarks are created

        // extract received favorites UUIDs
        let favoritesUUIDs: [String] = metadata.receivedByUUID[BookmarkEntity.Constants.favoritesFolderID]?.children ?? []
        // populate favorites
        if !favoritesUUIDs.isEmpty {
            guard let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(context) else {
                // Error - unable to process favorites
                return
            }

            favoritesUUIDs.forEach { uuid in
                if let bookmark = metadata.entitiesByUUID[uuid] {
                    bookmark.removeFromFavorites()
                    bookmark.addToFavorites(favoritesRoot: favoritesFolder)
                }
            }
        }

        for folderUUID in metadata.childrenToParentFoldersMap.keys {
            if let folder = metadata.entitiesByUUID[folderUUID], let bookmarks = metadata.childrenToParentFoldersMap[folderUUID] {
                for bookmarkUUID in bookmarks {
                    if let bookmark = metadata.entitiesByUUID[bookmarkUUID] {
                        bookmark.parent = nil
                        folder.addToChildren(bookmark)
                    }
                }
            }
        }
    }

    private func processExistingEntities(metadata: inout ReceivedBookmarksMetadata, in context: NSManagedObjectContext, using crypter: Crypting) {
        let bookmarks = BookmarkEntity.fetchBookmarks(with: metadata.allReceivedIDs, in: context)

        metadata.entitiesByUUID = bookmarks.reduce(into: .init()) { partialResult, bookmark in
            guard let uuid = bookmark.uuid else {
                return
            }
            if let syncable = metadata.receivedByUUID[uuid] {
                try? bookmark.update(with: syncable, in: context, using: crypter)
            }
            partialResult[uuid] = bookmark
        }
    }

    private func processTopLevelFolder(_ topLevelFolderSyncable: Syncable, metadata: inout ReceivedBookmarksMetadata, in context: NSManagedObjectContext, using crypter: Crypting) {
        guard let topLevelFolderUUID = topLevelFolderSyncable.uuid else {
            return
        }
        var queues: [[String]] = [topLevelFolderSyncable.children]
        var parentUUIDs: [String] = [topLevelFolderUUID]

        while !queues.isEmpty {
            var queue = queues.removeFirst()
            let parentUUID = parentUUIDs.removeFirst()
            let parent = BookmarkEntity.fetchFolder(withUUID: parentUUID, in: context)
            assert(parent != nil)

            while !queue.isEmpty {
                let syncableUUID = queue.removeLast()
                guard let syncable = metadata.receivedByUUID[syncableUUID] else {
                    continue
                }

                if let deduplicatedEntity = BookmarkEntity.deduplicatedEntity(with: syncable, parentID: parentUUID, in: context, using: crypter) {

                    if let oldUUID = deduplicatedEntity.uuid {
                        metadata.entitiesByUUID.removeValue(forKey: oldUUID)
                    }
                    metadata.entitiesByUUID[syncableUUID] = deduplicatedEntity
                    deduplicatedEntity.uuid = syncableUUID

                } else if let existingEntity = metadata.entitiesByUUID[syncableUUID] {

                    try? existingEntity.update(with: syncable, in: context, using: crypter)

                } else if !syncable.isDeleted {

                    let newEntity = BookmarkEntity.make(withUUID: syncableUUID, isFolder: syncable.isFolder, in: context)
                    newEntity.parent = parent
                    try? newEntity.update(with: syncable, in: context, using: crypter)
                    metadata.entitiesByUUID[syncableUUID] = newEntity
                }

                if syncable.isFolder, !syncable.children.isEmpty {
                    queues.append(syncable.children)
                    parentUUIDs.append(syncableUUID)
                }
            }
        }
    }

    private let database: CoreDataDatabase
    private let metadataStore: SyncMetadataStore
    private let reloadBookmarksAfterSync: () -> Void
}
