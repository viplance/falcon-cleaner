import AppKit
import SwiftUI

/// Tracks this view's window so another active window cannot keep its polling alive.
struct WindowActivityObserver: NSViewRepresentable {
    @Binding var isActive: Bool

    func makeNSView(context: Context) -> NSView {
        let view = ActivityView()
        view.onActivityChange = { isActive = $0 }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ActivityView else { return }
        view.onActivityChange = { isActive = $0 }
        view.reportActivity()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        guard let view = nsView as? ActivityView else { return }
        view.onActivityChange = nil
        NotificationCenter.default.removeObserver(view)
    }

    private final class ActivityView: NSView {
        var onActivityChange: ((Bool) -> Void)?
        private var lastActivity: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self)
            if let window {
                for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                             NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                             NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                    center.addObserver(self, selector: #selector(activityChanged(_:)), name: name, object: window)
                }
                for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                             NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                    center.addObserver(self, selector: #selector(activityChanged(_:)), name: name, object: NSApp)
                }
            }
            reportActivity()
        }

        @objc private func activityChanged(_ notification: Notification) {
            reportActivity(closing: notification.name == NSWindow.willCloseNotification)
        }

        func reportActivity(closing: Bool = false) {
            let active = !closing && NSApp.isActive && !NSApp.isHidden
                && window?.isKeyWindow == true && window?.isVisible == true
                && window?.isMiniaturized == false
            guard active != lastActivity else { return }
            lastActivity = active
            // A representable may report its initial state during a SwiftUI update.
            DispatchQueue.main.async { [weak self] in self?.onActivityChange?(active) }
        }
    }
}
