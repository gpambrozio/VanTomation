//
//  IntercomManager.swift
//  VanTonationCommons
//
//  Created by Gustavo Ambrozio on 12/7/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import Foundation
import MMWormhole

public class IntercomManager {

    private static let wormhole = MMWormhole(applicationGroupIdentifier: "group.br.eng.gustavo.VanTomation", optionalDirectory: "wormhole")

    public static func post(message: AnyObject, with id: String) {
        wormhole.passMessageObject("", identifier: id)

    }

    public static func listenToMessages(with id: String) {
        wormhole.listenForMessageWithIdentifier(id, listener: { (messageObject) -> Void in

        })
    }
}
