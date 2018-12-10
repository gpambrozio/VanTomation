//
//  LightsIntentHandler.swift
//  AutomationIntents
//
//  Created by Gustavo Ambrozio on 12/6/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import Foundation
import VanTomationCommons

class LightsIntentHandler: NSObject, LightsIntentHandling {
    func confirm(intent: LightsIntent,
                 completion: @escaping (LightsIntentResponse) -> Void) {
        completion(LightsIntentResponse(code: .ready, userActivity: nil))

    }

    func handle(intent: LightsIntent,
                completion: @escaping (LightsIntentResponse) -> Void) {
        completion(.success(onOff: intent.onOff))
    }
}
