//
//  ViewController.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 7/2/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import UIKit
import fluid_slider

class ViewController: UIViewController {

    private let masterManager = MasterManager.shared
    private var pickedColor: UIColor?

    @IBOutlet private var stripSelection: UISegmentedControl!
    @IBOutlet private var ledColorMode: UISegmentedControl!
    @IBOutlet private var colorPicker: ColorPickerImageView!
    @IBOutlet private var brightnessSlider: Slider!
    @IBOutlet private var speedSlider: Slider!
    @IBOutlet private var connectedLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        colorPicker.pickedColorClosure = { [weak self] color in
            guard let `self` = self else { return }
            self.ledColorMode.selectedSegmentIndex = 0
            self.pickedColor = color
            self.brightnessSlider.contentViewColor = color
            self.didChangeLedMode()
        }

        brightnessSlider.attributedTextForFraction = { fraction in
            let formatter = NumberFormatter()
            formatter.maximumIntegerDigits = 3
            formatter.maximumFractionDigits = 0
            let string = formatter.string(from: (fraction * 100) as NSNumber) ?? ""
            return NSAttributedString(string: string, attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .bold),
                                                                   .foregroundColor: UIColor.black])
        }
        brightnessSlider.setMinimumLabelAttributedText(NSAttributedString(string: "", attributes: [:]))
        brightnessSlider.setMaximumLabelAttributedText(NSAttributedString(string: "", attributes: [:]))
        brightnessSlider.fraction = 0.5
        brightnessSlider.contentViewColor = .blue
        brightnessSlider.valueViewColor = .white

        speedSlider.attributedTextForFraction = { fraction in
            let formatter = NumberFormatter()
            formatter.maximumIntegerDigits = 3
            formatter.maximumFractionDigits = 0
            let string = formatter.string(from: (fraction * 100) as NSNumber) ?? ""
            return NSAttributedString(string: string, attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .bold),
                                                                   .foregroundColor: UIColor.black])
        }
        speedSlider.setMinimumLabelAttributedText(NSAttributedString(string: "", attributes: [:]))
        speedSlider.setMaximumLabelAttributedText(NSAttributedString(string: "", attributes: [:]))
        speedSlider.fraction = 0.5
        speedSlider.contentViewColor = .clear
        speedSlider.valueViewColor = .white

        masterManager.devicesClosure = { [connectedLabel] devices in
            connectedLabel?.text = "Connected: \(devices)"
        }
    }

    deinit {
        masterManager.devicesClosure = nil
    }

    @IBAction func lock() {
        masterManager.send(command: "PL")
    }
    
    @IBAction func unlock() {
        masterManager.send(command: "PU")
    }

    @IBAction func didChangeLedMode() {
        let colors = UnsafeMutablePointer<CGFloat>.allocate(capacity: 3)
        defer {
            colors.deallocate()
        }

        let strip = stripSelection.selectedSegmentIndex == 0 ? "I" : "O"

        let command: String
        switch ledColorMode.selectedSegmentIndex {
        case 0:
            speedSlider.isHidden = true
            guard let color = pickedColor,
                color.getRed(colors.advanced(by: 0),
                             green: colors.advanced(by: 1),
                             blue: colors.advanced(by: 2),
                             alpha: nil) else { return }

            command = String(format: "LC\(strip)%02X%02X%02X%02X",
                             Int(brightnessSlider.fraction * 40),
                             Int(colors[0] * 255),
                             Int(colors[1] * 255),
                             Int(colors[2] * 255))
        case 1:
            speedSlider.isHidden = false
            command = String(format: "LR\(strip)%02X%02X",
                             Int(brightnessSlider.fraction * 40),
                             Int(speedSlider.fraction * 200))

        case 2:
            speedSlider.isHidden = false
            command = String(format: "LT\(strip)%02X%02X",
                Int(brightnessSlider.fraction * 40),
                Int(speedSlider.fraction * 200 + 24))
        default:
            command = ""
        }

        guard command.count > 0 else { return }
        masterManager.send(command: command)
    }
}

