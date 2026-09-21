//
//  cubeguideApp.swift
//  cubeguide
//
//  Created by Mehade Hasan on 9/20/26.
//

import SwiftUI

@main
struct cubeguideApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
            if let scenario = CalculationTestScenario.requested {
                CalculationTestHost(scenario: scenario)
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
