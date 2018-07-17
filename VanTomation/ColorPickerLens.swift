//
//  ColorPickerLens.swift
//  VanTomation
//
//  Created by Gustavo Ambrozio on 7/14/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import Foundation
import UIKit

class ColorPickerLens: UIView {
    public var color: UIColor = .white {
        didSet {
            setNeedsDisplay()
        }
    }

    private func commonInit() {
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()

        let radius = min(rect.width, rect.height) / 2.0

        context.setShadow(offset: CGSize(width: 2, height: 2), blur: 0.5)

        context.move(to: CGPoint(x: radius, y: rect.height))
        context.addArc(center: CGPoint(x: 2 * radius, y: rect.height),
                 radius: radius,
                 startAngle: CGFloat.pi,
                 endAngle: CGFloat.pi * 5 / 4,
                 clockwise: false)
        context.addArc(center: CGPoint(x: radius, y: rect.height - radius * 1.7071067811865),
                 radius: radius - 2,
                 startAngle: CGFloat.pi / 4,
                 endAngle: CGFloat.pi * 3 / 4,
                 clockwise: true)
        context.addArc(center: CGPoint(x: 0, y: rect.height),
                 radius: radius,
                 startAngle: CGFloat.pi / -4,
                 endAngle: 0,
                 clockwise: false)

        color.setFill()
        UIColor(white:0.2, alpha:1.0).setStroke()
        context.setLineWidth(2)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.drawPath(using: .fillStroke)
        context.endTransparencyLayer()

        context.restoreGState()
    }
}
