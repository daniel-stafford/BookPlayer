//
//  SyncJobScheduler.swift
//  BookPlayer
//
//  Created by gianni.carlo on 4/8/22.
//  Copyright © 2022 Tortuga Power. All rights reserved.
//

import Combine
import Foundation
import SwiftQueue

public protocol JobSchedulerProtocol {
  func scheduleFileUploadJob(for relativePath: String, remoteUrlPath: String)
  func scheduleMetadataUploadJob(for item: SyncableItem)
}

public class SyncJobScheduler: JobSchedulerProtocol {
  let metadataQueueManager: SwiftQueueManager
  let fileUploadQueueManager: SwiftQueueManager
  let metadataJobsPersister: UserDefaultsPersister
  let fileUploadJobsPersister: UserDefaultsPersister
//  let folderQueueManager: SwiftQueueManager
//  let progressQueueManager: SwiftQueueManager

  private var disposeBag = Set<AnyCancellable>()

  public init() {
    let metadataJobsPersister = UserDefaultsPersister(key: LibraryItemMetadataUploadJob.type)
    self.metadataQueueManager = SwiftQueueManagerBuilder(creator: LibraryItemMetadataUploadJobCreator())
      .set(persister: metadataJobsPersister)
      .build()
    self.metadataJobsPersister = metadataJobsPersister

    let fileUploadJobsPersister = UserDefaultsPersister(key: LibraryItemFileUploadJob.type)
    self.fileUploadQueueManager = SwiftQueueManagerBuilder(creator: LibraryItemFileUploadJobCreator())
      .set(persister: fileUploadJobsPersister)
      .build()
    self.fileUploadJobsPersister = fileUploadJobsPersister
    bindObservers()
  }

  private func bindObservers() {
    NotificationCenter.default.publisher(for: .logout, object: nil)
      .sink(receiveValue: { [weak self] _ in
        self?.metadataQueueManager.cancelAllOperations()
        self?.metadataJobsPersister.clearAll()
        self?.fileUploadQueueManager.cancelAllOperations()
        self?.fileUploadJobsPersister.clearAll()
      })
      .store(in: &disposeBag)
  }

  public func scheduleFileUploadJob(for relativePath: String, remoteUrlPath: String) {
    JobBuilder(type: LibraryItemFileUploadJob.type)
      .singleInstance(forId: relativePath)
      .persist()
      .retry(limit: .limited(3))
      .internet(atLeast: .wifi)
      .with(params: [
        "relativePath": relativePath,
        "remoteUrlPath": remoteUrlPath
      ])
      .schedule(manager: fileUploadQueueManager)
  }

  public func scheduleMetadataUploadJob(for item: SyncableItem) {
    var parameters: [String: Any] = [
      "relativePath": item.relativePath,
      "originalFileName": item.originalFileName,
      "title": item.title,
      "details": item.details,
      "currentTime": item.currentTime,
      "duration": item.duration,
      "percentCompleted": item.percentCompleted,
      "isFinished": item.isFinished,
      "orderRank": item.orderRank,
      "type": item.type.rawValue
    ]

    if let lastPlayTimestamp = item.lastPlayDateTimestamp {
      parameters["lastPlayDateTimestamp"] = Int(lastPlayTimestamp)
    }

    if let speed = item.speed {
      parameters["speed"] = speed
    }

    JobBuilder(type: LibraryItemMetadataUploadJob.type)
      .singleInstance(forId: item.relativePath)
      .persist()
      .retry(limit: .limited(3))
      .internet(atLeast: .wifi)
      .with(params: parameters)
      .schedule(manager: metadataQueueManager)
  }
}
