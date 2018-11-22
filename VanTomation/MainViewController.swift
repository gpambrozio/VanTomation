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
                        let networks = try JSONDecoder().decode([[String]].self, from: data)
                        self.wifiNetworks = networks.compactMap { WifiNetwork(from: $0) }.sorted()
                        self.wifiTable.reloadData()
                    }
                } catch let error {
                    print("\(error)")
                }
            } else {
                print("command: \(command)")
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
}

extension MainViewController: UITableViewDelegate {

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

struct WifiNetwork {
    let name: String
    let open: Bool
    let strength: Int
    let frequency: Int

    init?(from network: [String]) {
        name = network[4]
        open = network[3] == "[ESS]" || network[3].isEmpty
        guard !name.isEmpty,
            name != "agnes",
            let strength = Int(network[2]),
            let frequency = Int(network[1]) else { return nil }
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
    @IBOutlet private var networkSecurity: UILabel!

    func fill(with network: WifiNetwork) {
        networkName.text = network.name
        networkSecurity.text = "\(network.strength)\(network.open ? "O" : "L")"
    }
}
