//
//  MainViewController.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 8/18/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import UIKit
import RxSwift

class MainViewController: UIViewController {
    private let masterManager = MasterManager.shared

    @IBOutlet private var connectedLabel: UILabel!
    @IBOutlet private var temperatureFahrenheitLabel: UILabel!
    @IBOutlet private var temperatureCelsiusLabel: UILabel!
    @IBOutlet private var humidityLabel: UILabel!

    @IBOutlet private var targetTemperatureLabel: UILabel!
    @IBOutlet private var thermostatSwitch: UISwitch!
    @IBOutlet private var wifiLabel: UILabel!
    @IBOutlet private var wifiTable: UITableView!

    private var wifiNetworks = [WifiNetwork]()

    private let disposeBag = DisposeBag()

    private func updateWifiLabel() {
        guard let wifiNetwork = wifiNetwork else {
            wifiLabel.text = "Disconnected"
            return
        }
        guard let wifiIp = wifiIp, !wifiIp.isEmpty else {
            wifiLabel.text = wifiNetwork
            return
        }
        wifiLabel.text = "\(wifiNetwork) (\(wifiIp))"
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

    private var thermostatOn = false {
        didSet {
            thermostatSwitch.isOn = thermostatOn
        }
    }
    private var targetTemperature = 71 {
        didSet {
            targetTemperatureLabel.text = "\(targetTemperature)°F"
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        masterManager.connectedStream.subscribe(onNext: { [weak self] connected in
            guard let self = self else { return }
            self.connectedLabel.text = connected ? "Connected" : "Disconnected"
            if !connected {
                self.wifiNetworks = []
                self.wifiTable.reloadData()
                self.wifiIp = nil
                self.wifiNetwork = nil
                self.temperatureFahrenheitLabel.text = "?"
                self.temperatureCelsiusLabel.text = "?"
                self.humidityLabel.text = "?"
            }
        }).disposed(by: disposeBag)

        masterManager.commandsStream.subscribe(onNext: { [weak self] command in
            guard let self = self else { return }
            let commandData = command[command.index(command.startIndex, offsetBy: 2)...]
            if command.starts(with: "Dv") {
                self.connectedLabel.text = "Connected: \(commandData)"
            } else if command.starts(with: "Ti") {
                let temperatureF = (Double(commandData) ?? 0) / 10.0
                self.temperatureFahrenheitLabel.text = String(format: "i %.1f°F", temperatureF)
                self.navigationController?.tabBarItem.badgeValue = "\(temperatureF)"
            } else if command.starts(with: "To") {
                let temperatureF = (Double(commandData) ?? 0) / 10.0
                self.temperatureCelsiusLabel.text = String(format: "o %.1f°F", temperatureF)
            } else if command.starts(with: "Hm") {
                let humidity = (Double(commandData) ?? 0) / 10.0
                self.humidityLabel.text = String(format: "%.1f%%", humidity)
            } else if command.starts(with: "TO") {
                self.thermostatSwitch.isOn = commandData[commandData.startIndex] == "1"
            } else if command.starts(with: "Tt") {
                self.targetTemperature = (Int(commandData) ?? 0) / 10
            } else if command.starts(with: "Ws") {
                self.wifiNetwork = commandData.isEmpty ? nil : "\(commandData)"
            } else if command.starts(with: "Wi") {
                self.wifiIp = "\(commandData)"
            } else if command.starts(with: "WS") {
                do {
                    if let data = commandData.data(using: .utf8) {
                        let networks = try JSONDecoder().decode([[StringOrInt]].self, from: data)
                        self.wifiNetworks = networks.compactMap { WifiNetwork(from: $0) }.sorted()
                        self.wifiTable.reloadData()
                    }
                } catch let error {
                    print("Error decoding json: \(error)")
                }
            } else {
                print("unknown command: \(command)")
            }
        }).disposed(by: disposeBag)

        masterManager.statusStream.subscribe(onNext: { [weak self] status in
            guard let self = self else { return }
            self.connectedLabel.text = status
        }).disposed(by: disposeBag)

        updateWifiLabel()
    }

    @IBAction func lock() {
        masterManager.send(command: "PL")
    }

    @IBAction func unlock() {
        masterManager.send(command: "PU")
    }

    @IBAction func targetPlus() {
        targetTemperature += 1
        sendThermostatCommand()
    }

    @IBAction func targetMinus() {
        targetTemperature -= 1
        sendThermostatCommand()
    }

    @IBAction func thermostatSwitchChanged() {
        thermostatOn = thermostatSwitch.isOn
        sendThermostatCommand()
    }

    private func sendThermostatCommand() {
        let target = targetTemperature * 10
        let command = String(format: "TT\(thermostatOn ? "1" : "0")%04X", target)
        masterManager.send(command: command)
    }

    private func addNetwork(_ network: WifiNetwork, password: String = "") {
        masterManager.send(command: "WA\(network.name),\(password)")
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

extension MainViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let network = wifiNetworks[indexPath.row]
        if network.open {
            self.addNetwork(network)
        } else {
            let alert = UIAlertController(title: nil,
                                          message: "What's the password?",
                                          preferredStyle: .alert)
            alert.addTextField()
            alert.addAction(.init(title: "Cancel", style: .cancel, handler: { _ in alert.dismiss(animated: true) }))
            alert.addAction(.init(title: "OK", style: .default, handler: { [weak self] _ in
                guard let textField = alert.textFields?.first, let text = textField.text else { return }
                guard let self = self else { return }
                self.addNetwork(network, password: text)
                alert.dismiss(animated: true)
            }))
            self.present(alert, animated: true)
        }

        return nil
    }
}

extension MainViewController: UITableViewDataSource {
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

    init?(from network: [StringOrInt]) {
        guard let name = network[0].asString,
            !name.isEmpty,
            name != "agnes",
            let open = network[3].asInt,
            let strength = network[2].asInt,
            let frequency = network[1].asInt else { return nil }
        self.name = name
        self.open = open != 0
        self.strength = strength
        self.frequency = frequency
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

class WifiCell: UITableViewCell {
    @IBOutlet private var networkName: UILabel!
    @IBOutlet private var networkStrenght: UILabel!
    @IBOutlet private var networkFrequency: UILabel!
    @IBOutlet private var openImage: UIImageView!

    fileprivate func fill(with network: WifiNetwork) {
        networkName.text = network.name
        networkStrenght.text = "\(network.strength)"
        networkFrequency.text = network.frequency >= 5000 ? "5k" : "2k"
        openImage.image = UIImage.init(named: network.open ? "unlocked" : "locked")!
    }
}
