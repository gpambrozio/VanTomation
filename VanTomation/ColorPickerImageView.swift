//
//  ColorPickerImageView.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 7/14/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import Foundation
import UIKit

class ColorPickerImageView: UIImageView {
    typealias TouchedColorClosure = (_ color: UIColor, _ point: CGPoint) -> Void
    typealias PickedColorClosure = (_ color: UIColor) -> Void

    private let pickerLens = ColorPickerLens(frame: CGRect(x: 0, y: 0, width: 66, height: 115))
    private let data = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)

    var pickedColorClosure: PickedColorClosure? = nil

    private func commonInit() {
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = false
        clipsToBounds = false
        pickerLens.alpha = 0.0
        addSubview(pickerLens)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    deinit {
        data.deallocate()
    }

    private func showLens(with color: UIColor?, at point: CGPoint?) {
        guard let color = color, let point = point else {
            pickerLens.alpha = 0
            return
        }
        pickerLens.frame = CGRect(x: point.x - self.pickerLens.frame.size.width / 2,
                                  y: point.y - self.pickerLens.frame.size.height,
                                  width: self.pickerLens.frame.size.width,
                                  height: self.pickerLens.frame.size.height)
        pickerLens.color = color
        pickerLens.alpha = 1
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        let color = pixelColor(at: point)
        showLens(with: color, at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        let color = pixelColor(at: point)
        showLens(with: color, at: point)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        showLens(with: nil, at: nil)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        let color = pixelColor(at: point)
        showLens(with: nil, at: nil)
        if let color = color {
            pickedColorClosure?(color)
        }
    }

    private func pixelColor(at touch: CGPoint) -> UIColor? {
        guard let image = image,
            let cgImage = image.cgImage else {
            return nil
        }

        // For some reason when alpha is zero the data doesn't change in the draw call
        // Force resetting the alpha value is enough to know it didn't draw anything.
        data[0] = 0;

        // For retina images scale is 2.0f
        var point = touch
        point.x *= image.scale * image.size.width / bounds.width
        point.y *= image.scale * image.size.height / bounds.height

        // Create the bitmap context. We want pre-multiplied ARGB, 8-bits
        // per component. Regardless of what the source image format is
        // (CMYK, Grayscale, and so on) it will be converted over to the format
        // specified here by CGBitmapContextCreate.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgctx = CGContext(
            data: data,
            width: 1,    // width
            height: 1,    // height
            bitsPerComponent: 8,       // bits per component
            bytesPerRow: 4,    // bytesPerRow
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return nil
        }

        // subImage contains only one pixel at the position we touched.
        guard let subImage = cgImage.cropping(to: CGRect(x: floor(point.x), y: floor(point.y), width: 1, height: 1)) else { return nil }

        // Draw the image to the bitmap context. Once we draw, the memory
        // allocated for the context for rendering will then contain the
        // raw image data in the specified color space (ARGB).
        cgctx.draw(subImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        // If alpha is lower than a specified threshold it means
        // it's a transparent area and I should ignore it
        let alpha = data[0]
        if (alpha >= 220) {
            let color = UIColor(red: CGFloat(data[1]) / 255,
                                green: CGFloat(data[2]) / 255,
                                blue: CGFloat(data[3]) / 255,
                                alpha: CGFloat(alpha) / 255)
            return color
        }

        return nil
    }
}
