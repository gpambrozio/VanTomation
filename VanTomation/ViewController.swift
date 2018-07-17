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

    @IBOutlet weak var ledColorMode: UISegmentedControl!
    @IBOutlet weak var colorPicker: ColorPickerImageView!
    @IBOutlet weak var speedSlider: Slider!
    @IBOutlet weak var brightnessSlider: Slider!
    @IBOutlet weak var connectedLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        colorPicker.pickedColorClosure = { [weak self] color in
            self?.pickedColor = color
            self?.brightnessSlider.contentViewColor = color
            self?.didChangeLedMode()
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

        masterManager.devicesClosure = { [connectedLabel] devices in
            connectedLabel?.text = "Connected: \(devices)"
        }
    }

    deinit {
        masterManager.devicesClosure = nil
    }

    private func hex<T>(_ n: T) -> String where T : FixedWidthInteger, T : UnsignedInteger {
        let ret = String.init(n, radix: 16, uppercase: true)
        if ret.count % 2 == 0 {
            return ret
        }
        return "0\(ret)"
    }

    @IBAction func didChangeLedMode() {
        let colors = UnsafeMutablePointer<CGFloat>.allocate(capacity: 3)
        defer {
            colors.deallocate()
        }

        guard let color = pickedColor,
            color.getRed(colors.advanced(by: 0),
                         green: colors.advanced(by: 1),
                         blue: colors.advanced(by: 2),
                         alpha: nil) else { return }

        let red = hex(UInt8(colors[0] * 255))
        let green = hex(UInt8(colors[1] * 255))
        let blue = hex(UInt8(colors[2] * 255))

        let command = "CO\(hex(UInt(brightnessSlider.fraction * 40)))\(red)\(green)\(blue)"
        print(command)
        masterManager.send(command: command)
    }
}

