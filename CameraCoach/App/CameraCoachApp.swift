// CameraCoachApp.swift
// App entry point — the @main attribute tells the Swift compiler that
// this struct is where execution begins, replacing the old UIApplicationMain()
// call. Every SwiftUI app has exactly one @main struct.
//
// The App protocol requires a `body` property that returns a Scene.
// WindowGroup is the standard scene type for iOS — it represents the
// single window your app gets on an iPhone.

import SwiftUI

@main
struct CameraCoachApp: App {
    var body: some Scene {
        WindowGroup {
            // ContentView is the root of the entire UI tree.
            // Everything else in the app is a child of this view.
            ContentView()
        }
    }
}
