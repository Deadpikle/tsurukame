// Copyright 2023 David Sansome
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

import Foundation

import Foundation
import WaniKaniAPI

class SubjectsByCategoryViewController: UITableViewController, SubjectDelegate {
  private var services: TKMServices!
  private(set) var category: SRSStageCategory!
  private var showAnswers: Bool!
  private var model: TableModel?
  private var answerSwitch: UISwitch!

  func setup(services: TKMServices, category: SRSStageCategory, showAnswers: Bool) {
    self.services = services
    self.category = category
    self.showAnswers = showAnswers
    setShowAnswers(showAnswers, animated: false)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.title = category.description

    let model = MutableTableModel(tableView: tableView)
    model.add(section: "Radicals")
    model.add(section: "Kanji")
    model.add(section: "Vocabulary")

    answerSwitch = UISwitch()
    answerSwitch.isOn = showAnswers
    answerSwitch.addTarget(self, action: #selector(answerSwitchChanged), for: .valueChanged)
    navigationItem.rightBarButtonItem = UIBarButtonItem(customView: answerSwitch)

    for assignment in services.localCachingClient.getAssignmentsInCategory(category: category) {
      guard let subject = services.localCachingClient.getSubject(id: assignment.subjectID)
      else {
        continue
      }
      if assignment.startedAt == 0 {
        continue
      }

      let section = subject.subjectType.rawValue - 1
      let item = SubjectModelItem(subject: subject, delegate: self, assignment: assignment,
                                  readingWrong: false, meaningWrong: false)
      item.showLevelNumber = true
      item.showAnswers = showAnswers
      if assignment.isBurned {
        item.gradientColors = TKMStyle.lockedGradient
      }
      model.add(item, toSection: section)
    }

    let comparator = { (a: SubjectModelItem, b: SubjectModelItem) -> Bool in
      guard let aAssignment = a.assignment,
            let bAssignment = b.assignment else {
        return false
      }

      if aAssignment.srsStage < bAssignment.srsStage { return true }
      if aAssignment.srsStage > bAssignment.srsStage { return false }
      if aAssignment.level < bAssignment.level { return true }
      if aAssignment.level > bAssignment.level { return false }
      return false
    }

    model.sort(section: 0, using: comparator)
    model.sort(section: 1, using: comparator)
    model.sort(section: 2, using: comparator)

    if category == SRSStageCategory.apprentice || category == SRSStageCategory.guru {
      for section in 0 ..< model.sectionCount {
        var lastAssignment: TKMAssignment?

        var itemIndex = 0
        while itemIndex < model.items(inSection: section).count {
          let item = model.items(inSection: section)[itemIndex]
          if let assignment = (item as! SubjectModelItem).assignment {
            if lastAssignment == nil || lastAssignment!.srsStage != assignment.srsStage ||
              lastAssignment!.isReviewStage != assignment.isReviewStage ||
              lastAssignment!.isLessonStage != assignment.isLessonStage {
              let label = assignment.srsStage.description
              model.insert(TKMListSeparatorItem(label: label), atIndex: itemIndex,
                           inSection: section)
              itemIndex += 1
            }
            lastAssignment = assignment
          }
          itemIndex += 1
        }
      }
    }

    self.model = model
  }

  @objc private func answerSwitchChanged() {
    setShowAnswers(answerSwitch.isOn, animated: true)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
  }

  func setShowAnswers(_ value: Bool, animated: Bool = false) {
    showAnswers = value
    guard let model = model else {
      return
    }

    for section in 0 ..< model.sectionCount {
      for item in model.items(inSection: section) {
        if let item = item as? SubjectModelItem {
          item.showAnswers = showAnswers
        }
      }
    }

    for cell in tableView.visibleCells {
      if let cell = cell as? SubjectModelView {
        cell.setShowAnswers(showAnswers, animated: animated)
      }
    }
  }

  // MARK: - SubjectDelegate

  func didTapSubject(_ subject: TKMSubject) {
    let vc = storyboard!
      .instantiateViewController(withIdentifier: "subjectDetailsViewController") as! SubjectDetailsViewController
    vc.setup(services: services, subject: subject)
    navigationController?.pushViewController(vc, animated: true)
  }
}
