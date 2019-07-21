//
//  MainViewController.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 8/18/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import UIKit
import RxSwift

class WiFiViewController: UIViewController {
    private let masterManager = MasterManager.shared

    @IBOutlet private var wifiLabel: UILabel!
    @IBOutlet private var wifiTable: UITableView!
    @IBOutlet private var wifiEnableSwitches: [UISwitch]!

    private enum Constants {
        static let wifiNetworkIdentifiers = ["myiPhone", "Gustavo's iPhone"]
    }

    private var wifiNetworks = [WifiNetwork]() {
        didSet {
            wifiTable.reloadData()
        }
    }

    private let disposeBag = DisposeBag()

    private func updateWifiLabel() {
        guard let wifiNetwork = wifiNetwork else {
            wifiLabel.text = "Disconnected"
            self.tabBarItem.badgeValue = nil
            return
        }
        self.tabBarItem.badgeValue = ""
        guard let wifiIp = wifiIp, !wifiIp.isEmpty else {
            wifiLabel.text = wifiNetwork
            return
        }
        guard let wifiPing = wifiPing else {
            wifiLabel.text = "\(wifiNetwork) (\(wifiIp))"
            return
        }
        wifiLabel.text = "\(wifiNetwork) (\(wifiIp)), \(wifiPing)ms"
    }

    private var wifiNetwork: String? {
        didSet {
            updateWifiLabel()
        }
    }
    private var wifiIp: String? {
        didSet {
            updateWifiLabel()
        }
    }
    private var wifiPing: Float? {
        didSet {
            updateWifiLabel()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        masterManager.connectedStream.subscribe(onNext: { [weak self] connected in
            guard !connected, let self = self else { return }
            self.wifiNetwork = nil
            self.wifiIp = nil
            self.wifiNetworks = []
        }).disposed(by: disposeBag)

        masterManager.commandsStream.subscribe(onNext: { [weak self] command in
            guard let self = self else { return }
            let commandData = command[command.index(command.startIndex, offsetBy: 2)...]
            if command.starts(with: "Ws") {
                self.wifiNetwork = commandData.isEmpty ? nil : "\(commandData)"
            } else if command.starts(with: "Wi") {
                self.wifiIp = "\(commandData)"
            } else if command.starts(with: "Wp") {
                self.wifiPing = Float("\(commandData)")
            } else if command.starts(with: "WS") {
                do {
                    if let data = commandData.data(using: .utf8) {
                        let networks = try JSONDecoder().decode([[StringOrInt]].self, from: data)
                        self.wifiNetworks = networks.compactMap { WifiNetwork(from: $0) }.sorted()
                    }
                } catch let error {
                    print("Error decoding json: \(error)")
                }
            }
        }).disposed(by: disposeBag)

        updateWifiLabel()
    }

    @IBAction func enableNetworkChanged(_ sender: UISwitch) {
        let wifiNetworkIdentifier = Constants.wifiNetworkIdentifiers[sender.tag]
        masterManager.send(command: "WE\(wifiNetworkIdentifier),\(sender.isOn ? 1 : 0)")
    }

    private func addNetwork(_ network: WifiNetwork, password: String = "") {
        masterManager.send(command: "WA\(network.name),\(password)")
    }

    private func removeNetwork(_ network: WifiNetwork) {
        masterManager.send(command: "WR\(network.name)")
    }
}

private struct StringOrInt: Decodable {
    let asString: String?
    let asInt: Int?

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        asInt = try? container.decode(Int.self)
        asString = try? container.decode(String.self)
    }
}

extension WiFiViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let network = wifiNetworks[indexPath.row]
        let alert: UIAlertController
        if network.hasPassword {
            alert = UIAlertController(title: nil,
                                      message: "Remove network?",
                                      preferredStyle: .alert)
            alert.addAction(.init(title: "Cancel", style: .cancel))
            alert.addAction(.init(title: "Yes", style: .default, handler: { [weak self] _ in
                self?.removeNetwork(network)
            }))
        } else if network.open {
            alert = UIAlertController(title: nil,
                                      message: "Are you sure?",
                                      preferredStyle: .alert)
            alert.addAction(.init(title: "Cancel", style: .cancel))
            alert.addAction(.init(title: "Yes", style: .default, handler: { [weak self] _ in
                self?.addNetwork(network)
            }))
        } else {
            alert = UIAlertController(title: nil,
                                      message: "What's the password?",
                                      preferredStyle: .alert)
            alert.addTextField()
            alert.addAction(.init(title: "Cancel", style: .cancel))
            alert.addAction(.init(title: "OK", style: .default, handler: { [weak self] _ in
                guard let textField = alert.textFields?.first,
                    let text = textField.text,
                    let self = self else { return }
                self.addNetwork(network, password: text)
            }))
        }
        self.present(alert, animated: true)

        return nil
    }
}

extension WiFiViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return wifiNetworks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WifiCell", for: indexPath) as! WifiCell
        cell.fill(with: wifiNetworks[indexPath.row])
        return cell
    }
}

private struct WifiNetwork {
    let name: String
    let open: Bool
    let strength: Int
    let frequency: Int
    let hasPassword: Bool

    init?(from network: [StringOrInt]) {
        guard let name = network[0].asString,
            !name.isEmpty,
            name != "agnes",
            let open = network[3].asInt,
            let strength = network[2].asInt,
            let frequency = network[1].asInt,
            let hasPassword = network[4].asInt else { return nil }
        self.name = name
        self.open = open != 0
        self.strength = strength
        self.frequency = frequency
        self.hasPassword = hasPassword != 0
    }
}

extension WifiNetwork: Comparable {
    static func < (lhs: WifiNetwork, rhs: WifiNetwork) -> Bool {
        if lhs.open && !rhs.open {
            return true
        }
        if !lhs.open && rhs.open {
            return false
        }
        return lhs.strength > rhs.strength
    }
}

// From https://stackoverflow.com/a/54844627/754013
extension UIFont {
    /// Returns a new font in the same family with the given symbolic traits,
    /// or `nil` if none found in the system.
    func withSymbolicTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let descriptorWithTraits = fontDescriptor.withSymbolicTraits(traits)
            else { return nil }
        return UIFont(descriptor: descriptorWithTraits, size: 0)
    }
}

class WifiCell: UITableViewCell {
    @IBOutlet private var networkName: UILabel!
    @IBOutlet private var networkStrenght: UILabel!
    @IBOutlet private var networkFrequency: UILabel!
    @IBOutlet private var openImage: UIImageView!

    fileprivate func fill(with network: WifiNetwork) {
        networkName.text = network.name
        networkStrenght.text = "\(network.strength)"
        networkFrequency.text = network.frequency >= 5000 ? "5G" : "2G"
        openImage.image = network.open ? nil : UIImage(named: "locked")!
        networkName.font = network.hasPassword ? networkName.font.withSymbolicTraits(.traitBold) : networkName.font.withSymbolicTraits(.init(rawValue: 0))
    }
}
