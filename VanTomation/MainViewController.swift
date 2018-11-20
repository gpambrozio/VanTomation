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

    private let disposeBag = DisposeBag()

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

        masterManager.commandsStream.asObservable().subscribe(onNext: { [weak self] command in
            guard let `self` = self else { return }
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
            } else if command.starts(with: "To") {
                self.thermostatSwitch.isOn = commandData[commandData.startIndex] == "1"
            } else if command.starts(with: "Tt") {
                self.targetTemperature = (Int(commandData) ?? 0) / 10
            } else {
                print("command: \(command)")
            }
        }).disposed(by: disposeBag)

        masterManager.statusStream.asObservable().subscribe(onNext: { [weak self] status in
            guard let `self` = self else { return }
            self.connectedLabel.text = status
        }).disposed(by: disposeBag)
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
