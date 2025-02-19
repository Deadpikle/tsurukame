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

import Foundation
import UIKit
import WaniKaniAPI

class CreateCustomWordViewController: UITableViewController, TKMViewController {
  private var model: TableModel?
  private var notificationHandler: ((Bool) -> Void)?

  private var client: CustomWordCachingClient?

  private let kFontSize: CGFloat = {
    let bodyFontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
    return bodyFontDescriptor.pointSize
  }()

  // MARK: - TKMViewController

  var canSwipeToGoBack: Bool { true }

  // MARK: - UIViewController

  func setup(client: CustomWordCachingClient) {
    self.client = client
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let rightButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self,
                                          action: #selector(saveData))
    navigationItem.rightBarButtonItem = rightButtonItem
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = false
    rerender()
  }

  private func rerender() {
    let model = MutableTableModel(tableView: tableView)

    // TODO: Type of item, hide/show other fields as needed

    model.add(section: "Meaning")
    let meaningItem =
      EditableTextModelItem(text: NSAttributedString(string: ""),
                            placeholderText: "Above, up, over",
                            rightButtonImage: nil,
                            font: UIFont.systemFont(ofSize: kFontSize),
                            autoCapitalizationType: .none,
                            maximumNumberOfLines: 1)
    meaningItem.textChangedCallback = { (_: String) in
      // TODO: this
    }
    model.add(meaningItem)

    model.add(section: "Reading")
    let readingItem =
      EditableTextModelItem(text: NSAttributedString(string: ""),
                            placeholderText: "じょう",
                            rightButtonImage: nil,
                            font: UIFont.systemFont(ofSize: kFontSize),
                            autoCapitalizationType: .none,
                            maximumNumberOfLines: 1)
    readingItem.textChangedCallback = { (_: String) in
      // TODO: this
    }
    model.add(readingItem)

    model.add(section: "Meaning Explanation")
    let meaningExplanationItem =
      EditableTextModelItem(text: NSAttributedString(string: ""),
                            placeholderText: "You find a toe on the ground...",
                            rightButtonImage: nil,
                            font: UIFont.systemFont(ofSize: kFontSize),
                            autoCapitalizationType: .none,
                            maximumNumberOfLines: 5)
    meaningExplanationItem.textChangedCallback = { (_: String) in
      // TODO: this
    }
    model.add(meaningExplanationItem)

    model.add(section: "Reading Explanation")
    let readingExplanationItem =
      EditableTextModelItem(text: NSAttributedString(string: ""),
                            placeholderText: "This toe belongs to the local clumsy farmhand, Joe (じょう).",
                            rightButtonImage: nil,
                            font: UIFont.systemFont(ofSize: kFontSize),
                            autoCapitalizationType: .none,
                            maximumNumberOfLines: 5)
    readingExplanationItem.textChangedCallback = { (_: String) in
      // TODO: this
    }
    model.add(readingExplanationItem)

    self.model = model
    model.reloadTable()
  }

  @objc func saveData() {
    // TODO: create object and save
    var reading = TKMReading()
    reading.isPrimary = true
    reading.reading = "みにんぐ"
    var meaning = TKMMeaning()
    meaning.meaning = "meaning"
    meaning.type = .primary
    var subject = TKMSubject()
    subject.readings = [reading]
    subject.meanings = [meaning]
    subject.japanese = "jap"
    subject.level = 99

    var vocab = TKMVocabulary()
    vocab.partsOfSpeech = [.suruVerb] // TODO: let user choose part(s) of speech
    vocab.meaningExplanation = "meaning explain"
    vocab.readingExplanation = "reading explain"
    subject.vocabulary = vocab

//        var kanji = TKMKanji()
    let subjectID = client?.createSubject(subject: subject)
    subject.id = subjectID!
    var assignment = TKMAssignment()
    assignment.subjectID = subject.id
    assignment.subjectType = .vocabulary // TODO: choice
    assignment.level = 99
    assignment.availableAt = 1
    assignment.srsStageNumber = 0
    assignment.isKanaOnlyVocab = false // TODO: more choice stuff ramifications here
    _ = client?.createAssignment(assignment: assignment)
  }
}
