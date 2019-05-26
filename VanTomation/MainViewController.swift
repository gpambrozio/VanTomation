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

    @IBOutlet private var temperatureOutsideBackground: UIView!
    @IBOutlet private var temperatureInsideBackground: UIView!
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
            thermostatSlider.contentViewColor = Constants.offColor
            return
        }
        let fraction = 0.1 + 0.9 * CGFloat(targetTemperature - 45) / 30
        thermostatSlider.contentViewColor = MainViewController.getHeatMapColor(for: CGFloat(targetTemperature))
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
        thermostatSlider.contentViewColor = Constants.offColor
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
                self.temperatureInsideBackground.backgroundColor = MainViewController.getHeatMapColor(for: CGFloat(temperatureF))
                self.temperatureInsideLabel.text = String(format: "%.1f", temperatureF)
                self.tabBarItem.badgeValue = "\(temperatureF)"
            } else if command.starts(with: "To") {
                let temperatureF = (Double(commandData) ?? 0) / 10.0
                self.temperatureOutsideBackground.backgroundColor = MainViewController.getHeatMapColor(for: CGFloat(temperatureF))
                self.temperatureOutsideLabel.text = String(format: "%.1f", temperatureF)
            } else if command.starts(with: "Hm") {
                let humidity = (Double(commandData) ?? 0) / 10.0
                self.humidityLabel.text = String(format: "%.1f", humidity)
            } else if command.starts(with: "TO") {
                self.thermostatOn = commandData[commandData.startIndex] == "1"
            } else if command.starts(with: "Tt") {
                self.targetTemperature = Int(commandData) ?? 0
            } else if command.starts(with: "Mv") && commandData == "0" {
                self.tabBarController?.selectedViewController = self
            }
        }).disposed(by: disposeBag)

        masterManager.statusStream.subscribe(onNext: { [weak self] status in
            guard let self = self else { return }
            self.connectedLabel.text = status
        }).disposed(by: disposeBag)

        // Forces loading of all VCs
        tabBarController?.viewControllers?.forEach { let _ = $0.view }
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

    enum Constants {
        static var minTemp: CGFloat = 50.0
        static var maxTemp: CGFloat = 95.0
        static var offColor = UIColor(white: 0.8, alpha: 1)

        // A static array of 4 colors:  (blue,   green,  yellow,  red) using {r,g,b} for each.
        static var colors: [(CGFloat, CGFloat, CGFloat)] = [ (0, 0, 1), (0, 1, 0), (1, 1, 0), (1, 0, 0) ]
    }

    // Adapted from http://www.andrewnoske.com/wiki/Code_-_heatmaps_and_color_gradients
    private static func getHeatMapColor(for temperature: CGFloat) -> UIColor {
        var value = (temperature - Constants.minTemp) / (Constants.maxTemp - Constants.minTemp)

        let idx1: Int        // |-- Our desired color will be between these two indexes in "color".
        let idx2: Int        // |
        var fractBetween: CGFloat = 0;  // Fraction between "idx1" and "idx2" where our value is.

        if (value <= 0) {  // accounts for an input <=0
            idx1 = 0
            idx2 = 0
        } else if (value >= 1) {  // accounts for an input >=0
            idx1 = Constants.colors.count - 1
            idx2 = idx1
        } else {
            value *= CGFloat(Constants.colors.count - 1)
            idx1  = Int(value)                              // Our desired color will be after this index.
            idx2  = idx1 + 1                                // ... and before this index (inclusive).
            fractBetween = value - CGFloat(idx1)            // Distance between the two indexes (0-1).
        }

        let r = fractBetween * (Constants.colors[idx2].0 - Constants.colors[idx1].0) + Constants.colors[idx1].0
        let g = fractBetween * (Constants.colors[idx2].1 - Constants.colors[idx1].1) + Constants.colors[idx1].1
        let b = fractBetween * (Constants.colors[idx2].2 - Constants.colors[idx1].2) + Constants.colors[idx1].2

        return .init(red: r, green: g, blue: b, alpha: 1)
    }
}
