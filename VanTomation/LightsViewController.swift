//
//  ViewController.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 7/2/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import UIKit
import fluid_slider

class LightsViewController: UIViewController {

    enum Mode {
        case color
        case rainbow
        case theater
    }

    private let masterManager = MasterManager.shared

    private var mode = Mode.color {
        didSet {
            switch mode {
            case .color:
                speedStack.isHidden = true
                rainbowButton.isSelected = false
                theaterButton.isSelected = false
            case .rainbow:
                speedStack.isHidden = false
                rainbowButton.isSelected = true
                theaterButton.isSelected = false
            case .theater:
                speedStack.isHidden = false
                rainbowButton.isSelected = false
                theaterButton.isSelected = true
            }
            didChangeLedMode()
        }
    }

    private var pickedColor = UIColor.white {
        didSet {
            self.brightnessSlider.contentViewColor = pickedColor
        }
    }

    @IBOutlet private var stripSelection: UISegmentedControl!
    @IBOutlet private var colorPicker: ColorPickerImageView!
    @IBOutlet private var brightnessSlider: Slider!
    @IBOutlet private var speedSlider: Slider!
    @IBOutlet private var speedStack: UIStackView!

    @IBOutlet private var theaterButton: UIButton!
    @IBOutlet private var rainbowButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        colorPicker.pickedColorClosure = { [weak self] color in
            guard let self = self else { return }
            self.pickedColor = color
            self.mode = .color
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
    }

    @IBAction func didTapPower(_ sender: Any) {
        if brightnessSlider.fraction == 0 {
            brightnessSlider.fraction = 1
            pickedColor = .white
        } else {
            brightnessSlider.fraction = 0
        }
        mode = .color
    }

    @IBAction func didTapRainbow(_ sender: Any) {
        mode = .rainbow
    }

    @IBAction func didTapTheater(_ sender: Any) {
        mode = .theater
    }

    @IBAction func didChangeLedMode() {
        let strip = stripSelection.selectedSegmentIndex == 0 ? "I" : "O"

        let command: String
        switch mode {
        case .color:
            let colors = UnsafeMutablePointer<CGFloat>.allocate(capacity: 3)
            defer {
                colors.deallocate()
            }

            guard pickedColor.getRed(colors.advanced(by: 0),
                                     green: colors.advanced(by: 1),
                                     blue: colors.advanced(by: 2),
                                     alpha: nil) else { return }

            command = String(
                format: "L\(strip)C%02X00%02X%02X%02X",
                Int(brightnessSlider.fraction * 100),
                Int(colors[0] * 255),
                Int(colors[1] * 255),
                Int(colors[2] * 255))
        case .rainbow:
            command = String(
                format: "L\(strip)R%02X%02X000000",
                Int(brightnessSlider.fraction * 100),
                Int(speedSlider.fraction * 200))

        case .theater:
            command = String(
                format: "L\(strip)T%02X%02X000000",
                Int(brightnessSlider.fraction * 100),
                Int(speedSlider.fraction * 200 + 24))
        }

        masterManager.send(command: command)
    }
}
