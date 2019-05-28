//
//  ViewController.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 7/2/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import UIKit
import RxSwift
import fluid_slider

private extension UIColor {
    static func from(int color: Int) -> UIColor {
        let r = CGFloat(color / (256 * 256))
        let g = CGFloat((color / 256) % 256)
        let b = CGFloat(color % 256)

        return UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}

class LightsViewController: UIViewController {

    enum Mode {
        case color
        case rainbow
        case theater

        static func create(from mode: Character) -> Mode? {
            switch mode {
            case "C":
                return .color
            case "R":
                return .rainbow
            case "T":
                return .theater
            default:
                return nil
            }
        }
    }

    enum Strip: Hashable {
        case inside, outside

        var identifier: String {
            switch self {
            case .inside: return "I"
            case .outside: return "O"
            }
        }

        static func create(from strip: Character) -> Strip? {
            switch strip {
            case "I":
                return .inside
            case "O":
                return .outside
            default:
                return nil
            }
        }

        static func create(from tabIndex: Int) -> Strip? {
            switch tabIndex {
            case 0:
                return .inside
            case 1:
                return .outside
            default:
                return nil
            }
        }
    }

    private class StripState {
        var mode: Mode = .color
        var brightness: Int = 0
        var cycleDelay: Int = 0
        var color: UIColor = .white
    }

    private let masterManager = MasterManager.shared
    private let disposeBag = DisposeBag()

    private let strips: [Strip: StripState] = [
        .inside: StripState(),
        .outside: StripState(),
    ]

    private var selectedStrip: Strip? {
        return Strip.create(from: stripSelection.selectedSegmentIndex)
    }

    private var selectedStripState: StripState? {
        guard let selectedStrip = selectedStrip else {
            return nil
        }

        return strips[selectedStrip]
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
            guard let self = self, let selectedStripState = self.selectedStripState else { return }
            selectedStripState.color = color
            selectedStripState.mode = .color
            self.updateUI()
            self.updateCurrentStrip()
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

        masterManager.commandsStream.subscribe(onNext: { [weak self] command in
            guard let self = self else { return }
            if command.starts(with: "L") {
                let strip = command[command.index(command.startIndex, offsetBy: 1)]
                let mode = command[command.index(command.startIndex, offsetBy: 2)]
                let brightnessCycleColor = command[command.index(command.startIndex, offsetBy: 3)...].split(separator: ",").compactMap { Int($0) }

                if let mode = Mode.create(from: mode),
                    let strip = Strip.create(from: strip),
                    let stripMode = self.strips[strip],
                    brightnessCycleColor.count == 3 {

                    stripMode.brightness = brightnessCycleColor[0]
                    stripMode.cycleDelay = brightnessCycleColor[1]
                    stripMode.color = UIColor.from(int: brightnessCycleColor[2])
                    stripMode.mode = stripMode.brightness == 0 ? .color : mode

                    self.updateUI()
                }
            }
        }).disposed(by: disposeBag)
    }

    private func updateUI() {
        guard let selectedStripState = selectedStripState else {
            return
        }

        brightnessSlider.fraction = CGFloat(selectedStripState.brightness) / 100
        speedSlider.fraction = 1 - CGFloat(selectedStripState.cycleDelay) / 100
        switch selectedStripState.mode {
        case .color:
            brightnessSlider.contentViewColor = selectedStripState.color
            speedStack.isHidden = true
            rainbowButton.isSelected = false
            theaterButton.isSelected = false
        case .rainbow:
            brightnessSlider.contentViewColor = .white
            speedStack.isHidden = false
            rainbowButton.isSelected = true
            theaterButton.isSelected = false
        case .theater:
            brightnessSlider.contentViewColor = .white
            speedStack.isHidden = false
            rainbowButton.isSelected = false
            theaterButton.isSelected = true
        }
    }

    private func updateCurrentStrip() {
        guard let selectedStrip = selectedStrip,
            let selectedStripState = selectedStripState else {
                return
        }

        let command: String
        switch selectedStripState.mode {
        case .color:
            let colors = UnsafeMutablePointer<CGFloat>.allocate(capacity: 3)
            defer {
                colors.deallocate()
            }

            guard selectedStripState.color.getRed(colors.advanced(by: 0),
                                                  green: colors.advanced(by: 1),
                                                  blue: colors.advanced(by: 2),
                                                  alpha: nil) else { return }

            command = String(
                format: "L\(selectedStrip.identifier)C%02X00%02X%02X%02X",
                selectedStripState.brightness,
                Int(colors[0] * 255),
                Int(colors[1] * 255),
                Int(colors[2] * 255))

        case .rainbow:
            command = String(
                format: "L\(selectedStrip.identifier)R%02X%02X000000",
                selectedStripState.brightness,
                selectedStripState.cycleDelay)

        case .theater:
            command = String(
                format: "L\(selectedStrip.identifier)T%02X%02X000000",
                selectedStripState.brightness,
                selectedStripState.cycleDelay)
        }

        masterManager.send(command: command)
    }

    @IBAction func didTapPower(_ sender: Any) {
        guard let selectedStripState = selectedStripState else {
            return
        }

        if selectedStripState.brightness == 0 {
            selectedStripState.brightness = 100
            selectedStripState.color = .white
        } else {
            selectedStripState.brightness = 0
        }
        selectedStripState.mode = .color
        updateUI()
        updateCurrentStrip()
    }

    @IBAction func didTapRainbow(_ sender: Any) {
        selectedStripState?.mode = .rainbow
        updateUI()
        updateCurrentStrip()
    }

    @IBAction func didTapTheater(_ sender: Any) {
        selectedStripState?.mode = .theater
        updateUI()
        updateCurrentStrip()
    }

    @IBAction func didUpdateBrightness(_ sender: Any) {
        selectedStripState?.brightness = Int(brightnessSlider.fraction * 100)
        updateCurrentStrip()
    }

    @IBAction func didUpdateSpeed(_ sender: Any) {
        selectedStripState?.cycleDelay = Int((1 - speedSlider.fraction) * 100)
        updateCurrentStrip()
    }

    @IBAction func didChangeSelectedStrip(_ sender: Any) {
        updateUI()
    }
}
