//
//  MainViewController.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 8/18/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import UIKit

class MainViewController: UIViewController {
    private let masterManager = MasterManager.shared

    @IBOutlet private var connectedLabel: UILabel!
    @IBOutlet private var temperatureFahrenheitLabel: UILabel!
    @IBOutlet private var temperatureCelsiusLabel: UILabel!
    @IBOutlet private var humidityLabel: UILabel!

    @IBOutlet private var targetTemperatureLabel: UILabel!
    @IBOutlet private var thermostatSwitch: UISwitch!

    private var thermostatOn = false {
        didSet {
            thermostatSwitch.isOn = thermostatOn
            sendThermostatCommand()
        }
    }
    private var targetTemperature = 71 {
        didSet {
            targetTemperatureLabel.text = "\(targetTemperature)°F"
            sendThermostatCommand()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        masterManager.commandsStream.onSuccess { [weak self] command in
            guard let `self` = self else { return }
            let commandData = command[command.index(command.startIndex, offsetBy: 2)...]
            if command.starts(with: "CD") {
                self.connectedLabel.text = "Connected: \(commandData)"
            } else if command.starts(with: "CT") {
                let temperatureF = (Double(commandData) ?? 0) / 10.0
                let temperatureC = (temperatureF - 32.0) / 9.0 * 5.0
                self.temperatureFahrenheitLabel.text = String(format: "%.1f°F", temperatureF)
                self.temperatureCelsiusLabel.text = String(format: "%.1f°C", temperatureC)
                self.navigationController?.tabBarItem.badgeValue = "\(temperatureF)"
            } else if command.starts(with: "CH") {
                let humidity = (Double(commandData) ?? 0) / 10.0
                self.humidityLabel.text = String(format: "%.1f%%", humidity)
            } else if command.starts(with: "Ct") {
//                self.thermostatSwitch.isOn = commandData[commandData.startIndex] == "0"
//                self.targetTemperature = (Int(commandData[commandData.index(commandData.startIndex, offsetBy: 1)...]) ?? 0) / 10
            } else {
                print("command: \(command)")
            }
        }
        masterManager.statusStream.onSuccess { [weak self] status in
            guard let `self` = self else { return }
            self.connectedLabel.text = status
        }
    }

    @IBAction func lock() {
        masterManager.send(command: "PL")
    }

    @IBAction func unlock() {
        masterManager.send(command: "PU")
    }

    @IBAction func targetPlus() {
        targetTemperature += 1
    }

    @IBAction func targetMinus() {
        targetTemperature -= 1
    }

    @IBAction func thermostatSwitchChanged() {
        thermostatOn = thermostatSwitch.isOn
    }

    private func sendThermostatCommand() {
        let target = targetTemperature * 10
        let command = String(format: "TT\(thermostatOn ? "1" : "0")%04X", target)
        masterManager.send(command: command)
    }
}
