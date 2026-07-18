//
//  FalconCleanerApp.swift
//  FalconCleaner
//
//  Created by Dzmitry Sharko on 19.03.2026.
//

import SwiftUI
import AppKit

@main
struct FalconCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 820, minHeight: 480)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 960, height: 560)
    }
}

/// Stops the window from restoring into native full screen on launch.
/// Disables state restoration so the window always opens at the default size,
/// and exits full screen if macOS still restored the window into it.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isRestorable = false
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
