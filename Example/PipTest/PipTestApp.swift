//
//  PipTestApp.swift
//  PipTest
//
//  Created by Osl on 2021/7/19.
//

import SwiftUI
import IVTPictureInPicture

@main
struct PipTestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().onAppear(perform: {
                try? AVAudioSession.sharedInstance().setActive(true)
//                try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
                try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.mixWithOthers, .duckOthers, .defaultToSpeaker ,.allowAirPlay,.allowBluetooth, .allowBluetoothA2DP]);
                
            })
        }
    }
}
