//
//  MainViewController.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 8/18/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import UIKit
import RxSwift
import fluid_slider

class MainViewController: UIViewController {
    private let masterManager = MasterManager.shared

    @IBOutlet private var connectedLabel: UILabel!
    @IBOutlet private var temperatureInsideLabel: UILabel!
    @IBOutlet private var temperatureOutsideLabel: UILabel!
    @IBOutlet private var humidityLabel: UILabel!

    @IBOutlet private var thermostatSlider: Slider!

    private let disposeBag = DisposeBag()

    private func targetInF(from fraction: CGFloat) -> Int? {
        return fraction < 0.1 ? nil : Int((fraction - 0.1) / 0.9 * 30 + 45)
    }

    private func updateFractionFromTarget() {
        guard thermostatOn else {
            if thermostatSlider.fraction > 0.1 {
                thermostatSlider.fraction = 0
            }
            return
        }
        let fraction = 0.1 + 0.9 * CGFloat(targetTemperature - 45) / 30
        thermostatSlider.fraction = fraction
    }

    private var thermostatOn = false {
        didSet {
            updateFractionFromTarget()
        }
    }

    private var targetTemperature = 71 {
        didSet {
            updateFractionFromTarget()
        }
    }

    @IBAction func updateThermostat() {
        if let target = targetInF(from: thermostatSlider.fraction) {
            thermostatOn = true
            targetTemperature = target
        } else {
            thermostatOn = false
        }
        sendThermostatCommand()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        thermostatSlider.attributedTextForFraction = { [weak self] fraction in
            guard let self = self else { return NSAttributedString(string: "", attributes: [:]) }
            let formatter = NumberFormatter()
            formatter.maximumIntegerDigits = 2
            formatter.maximumFractionDigits = 0
            let output: String
            if let temp = self.targetInF(from: fraction) {
                output = formatter.string(from: temp as NSNumber) ?? ""
            } else {
                output = "Off"
            }
            return NSAttributedString(string: output, attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                                                                   .foregroundColor: UIColor(red: 97/255, green: 125/255, blue: 138/255, alpha: 1)])
        }
        thermostatSlider.setMinimumLabelAttributedText(NSAttributedString(string: "", attributes: [:]))
        thermostatSlider.setMaximumLabelAttributedText(NSAttributedString(string: "", attributes: [:]))
        thermostatSlider.fraction = 0
        thermostatSlider.contentViewColor = UIColor.init(white: 0.2, alpha: 1)
        thermostatSlider.valueViewColor = .white

        masterManager.connectedStream.subscribe(onNext: { [weak self] connected in
            guard let self = self else { return }
            self.connectedLabel.text = connected ? "Connected" : "Disconnected"
            if !connected {
                self.temperatureInsideLabel.text = "?"
                self.temperatureOutsideLabel.text = "?"
                self.humidityLabel.text = "?"
            }
            self.tabBarItem.badgeValue = connected ? "" : nil
        }).disposed(by: disposeBag)

        masterManager.commandsStream.subscribe(onNext: { [weak self] command in
            guard let self = self else { return }
            let commandData = command[command.index(command.startIndex, offsetBy: 2)...]
            if command.starts(with: "Dv") {
                self.connectedLabel.text = "Connected: \(commandData)"
            } else if command.starts(with: "Ti") {
                let temperatureF = (Double(commandData) ?? 0) / 10.0
                self.temperatureInsideLabel.text = String(format: "%.1f", temperatureF)
                self.tabBarItem.badgeValue = "\(temperatureF)"
            } else if command.starts(with: "To") {
                let temperatureF = (Double(commandData) ?? 0) / 10.0
                self.temperatureOutsideLabel.text = String(format: "%.1f", temperatureF)
            } else if command.starts(with: "Hm") {
                let humidity = (Double(commandData) ?? 0) / 10.0
                self.humidityLabel.text = String(format: "%.1f", humidity)
            } else if command.starts(with: "TO") {
                self.thermostatOn = commandData[commandData.startIndex] == "1"
            } else if command.starts(with: "Tt") {
                self.targetTemperature = Int(commandData) ?? 0
            } else {
                print("unknown command: \(command)")
            }
        }).disposed(by: disposeBag)

        masterManager.statusStream.subscribe(onNext: { [weak self] status in
            guard let self = self else { return }
            self.connectedLabel.text = status
        }).disposed(by: disposeBag)
    }

    @IBAction func lock() {
        masterManager.send(command: "PL")
    }

    @IBAction func unlock() {
        masterManager.send(command: "PU")
    }

    @IBAction func thermostatSwitchChanged() {
        sendThermostatCommand()
    }

    private func sendThermostatCommand() {
        let command = String(format: "TT\(thermostatOn ? "1" : "0")%04X", targetTemperature)
        masterManager.send(command: command)
    }
}
