//
//  IntentHandler.swift
//  AutomationIntents
//
//  Created by Gustavo Ambrozio on 12/6/18.
//  Copyright © 2018 Gustavo Ambrozio. All rights reserved.
//

import Intents
import VanTomationCommons

class IntentHandler: INExtension {
    
    override func handler(for intent: INIntent) -> Any {
        // This is the default implementation.  If you want different objects to handle different intents,
        // you can override this and return the handler you want for that particular intent.
        switch intent {
        case is LightsIntent:
            return LightsIntentHandler()
        default:
            return self
        }
    }
}
