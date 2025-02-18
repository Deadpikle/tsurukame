// Copyright 2025 David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import FMDB
import Foundation
import PromiseKit
import Reachability
import WaniKaniAPI

extension Notification.Name {
  static let cwccUnauthorized = Notification.Name(rawValue: "cwccUnauthorized")
  static let cwccAvailableItemsChanged = Notification.Name("cwccAvailableItemsChanged")
  static let cwccUserInfoChanged = Notification.Name("cwccUserInfoChanged")
  static let cwccSRSCategoryCountsChanged = Notification.Name("cwccSRSCategoryCountsChanged")
}

class CustomWordCachingClient: LocalCachingClient {
  private var db: FMDatabaseQueue!
  private var dateFormatter: DateFormatter
  private var user: TKMUser?

  @Cached(notificationName: .cwccAvailableItemsChanged) var availableCWSubjects: (lessonCount: Int,
                                                                                  reviewComposition: [
                                                                                    ReviewComposition
                                                                                  ])
  @Cached(notificationName: .cwccSRSCategoryCountsChanged) var srsCWCategoryCounts: [Int]

  @Cached var cwGuruKanjiCount: Int
  @Cached var cwApprenticeCount: Int
  @Cached var cwRecentLessonCount: Int
  @Cached(notificationName: .lccSRSCategoryCountsChanged) var cwSrsCategoryCounts: [Int]

  init(client: WaniKaniAPIClient, reachability: Reachability, user: TKMUser?) {
    dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    self.user = user

    super.init(client: client, reachability: reachability)

    openDatabase()

    _availableCWSubjects.updateBlock = {
      self.updateAvailableSubjects()
    }
    _cwGuruKanjiCount.updateBlock = {
      self.updateGuruKanjiCount()
    }
    _cwApprenticeCount.updateBlock = {
      self.updateApprenticeCount()
    }
    _cwRecentLessonCount.updateBlock = {
      self.updateRecentLessonCount()
    }
    _cwSrsCategoryCounts.updateBlock = {
      self.updateSrsCategoryCounts()
    }
  }

  override class func databaseUrl() -> URL {
    let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
    return URL(fileURLWithPath: "\(paths[0])/custom-word-cache.db")
  }

  private let schemas = [
    """
    CREATE TABLE assignments (
      id INTEGER PRIMARY KEY,
      subject_id INTEGER,
      pb BLOB
    );
    CREATE TABLE study_materials (
      id INTEGER PRIMARY KEY,
      pb BLOB
    );
    CREATE TABLE subjects (
      id INTEGER PRIMARY KEY,
      japanese TEXT,
      level INTEGER,
      type INTEGER,
      pb BLOB
    );
    CREATE TABLE subject_progress (
      id INTEGER PRIMARY KEY,
      level INTEGER,
      srs_stage INTEGER,
      subject_type INTEGER,
      last_mistake_time TIMESTAMP
    );

    CREATE INDEX idx_subject_id ON assignments (subject_id);
    CREATE INDEX idx_japanese ON subjects (japanese);
    CREATE INDEX idx_level ON subjects (level);
    """,
  ]

  private let kInitialSchemaVersion = 1
  private let kSchemaVersion = 1

  private func openDatabase() {
    db = FMDatabaseQueue(url: LocalCachingClient.databaseUrl())!
    db.inTransaction { db, _ in
      NSLog("Database URL: %@", LocalCachingClient.databaseUrl().absoluteString)
      // Get the current version.
      let targetVersion = kSchemaVersion
      var currentVersion = Int(db.userVersion)
      if currentVersion >= targetVersion {
        NSLog("Database up to date (version \(currentVersion))")
        return
      }

      // If the database doesn't exist yet its version will be 0. Jump to the last version the
      // schema was squashed.
      if currentVersion == 0 {
        currentVersion = kInitialSchemaVersion
      }

      // If the user is at a version before the schema was squashed, we can't upgrade, so delete the
      // database and crash so we can start over.
      if currentVersion < kInitialSchemaVersion {
        try! FileManager.default.removeItem(at: LocalCachingClient.databaseUrl())
        fatalError("Database version \(currentVersion) is too old")
      }

      // Update the table schema.
      for version in currentVersion ..< targetVersion {
        db.mustExecuteStatements(schemas[version - kInitialSchemaVersion])
      }

      // Set the new schema version
      db.mustExecuteUpdate("PRAGMA user_version = \(targetVersion)")
      NSLog("Database updated to schema version \(targetVersion)")
    }
  }

  override func getAllPendingProgress(limit _: Int?) -> [TKMProgress] {
    []
  }

  override func getUserInfo() -> TKMUser? {
    user
  }

  override func getAssignmentsAtUsersCurrentLevel() -> [TKMAssignment] {
    getAssignments(level: 1) // all custom words are level 1
  }

  override func getAudioUrls(levels _: [Int], voiceActorIds _: [Int64]) -> [AudioUrl] {
    []
  }

  override func getAllLevelProgressions() -> [TKMLevel] {
    []
  }

  override func sendProgress(_ progress: [TKMProgress]) -> Promise<Void> {
    db.inTransaction { db in
      for p in progress {
        // Delete the assignment. TODO: update
//          db.mustExecuteUpdate("DELETE FROM assignments WHERE id = ?", args: [p.assignment.id])

        var newSrsStage = p.assignment.srsStage
        if p.isLesson || (!p.meaningWrong && !p.readingWrong) {
          newSrsStage = newSrsStage.next
        } else if p.meaningWrong || p.readingWrong {
          newSrsStage = newSrsStage.previous
        }
        db
          .mustExecuteUpdate("REPLACE INTO subject_progress (id, level, srs_stage, subject_type, last_mistake_time) " +
            "VALUES (?, ?, ?, ?, ?)",
            args: [
              p.assignment.subjectID,
              p.assignment.level,
              newSrsStage.rawValue,
              p.assignment.subjectType.rawValue,
              !p.isLesson && (p.meaningWrong || p.readingWrong)
                ? dateFormatter.string(from: Date()) : "",
            ])
      }
    }

    _availableCWSubjects.invalidate()
    _cwSrsCategoryCounts.invalidate()
    _cwGuruKanjiCount.invalidate()
    _cwApprenticeCount.invalidate()
    _cwRecentLessonCount.invalidate()

    return Promise.value(())
  }

  override func updateStudyMaterial(_ material: TKMStudyMaterials) -> Promise<Void> {
    db.inTransaction { db in
      // Store the study material locally.
      db.mustExecuteUpdate("REPLACE INTO study_materials (id, pb) VALUES(?, ?)",
                           args: [material.subjectID, try! material.serializedData()])
    }
    return Promise.value(())
  }

  override func clearAllData() {}

  override func clearAllDataAndClose() {}

  override func getVoiceActors() -> [TKMVoiceActor] {
    []
  }

  override func sync(quick _: Bool, progress _: Progress) -> PMKFinalizer {
    Promise.value(()).cauterize()
  }
}
