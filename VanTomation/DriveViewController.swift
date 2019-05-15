//
//  DriveViewController.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 5/12/19.
//  Copyright © 2019 Gustavo Ambrozio. All rights reserved.
//

import Foundation
import UIKit
import RxSwift

class DriveController: UIViewController {
    private let masterManager = MasterManager.shared

    private var files = [String]() {
        didSet {
            tableView.reloadData()
        }
    }
    private let disposeBag = DisposeBag()

    @IBOutlet var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()

        masterManager.connectedStream.subscribe(onNext: { [weak self] connected in
            if !connected {
                self?.files = []
            }
        }).disposed(by: disposeBag)

        masterManager.commandsStream.subscribe(onNext: { [weak self] command in
            guard let self = self else { return }
            let commandData = command[command.index(command.startIndex, offsetBy: 2)...]
            if command.starts(with: "Mv") && commandData == "1" {

            } else if command.starts(with: "Pf") {
                do {
                    if let data = commandData.data(using: .utf8) {
                        let files = try JSONDecoder().decode([String].self, from: data)
                        self.files = files.sorted()
                    }
                } catch let error {
                    print("Error decoding json: \(error)")
                }
            }
        }).disposed(by: disposeBag)
    }
}

extension DriveController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let file = files[indexPath.row]
        masterManager.send(command: "Dp\(file)")

        return nil
    }
}

extension DriveController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return files.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DriveCell", for: indexPath) as! DriveCell
        cell.fill(with: files[indexPath.row])
        return cell
    }
}

class DriveCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!

    func fill(with file: String) {
        titleLabel.text = file
    }
}
