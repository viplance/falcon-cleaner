import AppKit
import SwiftUI

extension View {
    /// Apply before `.disabled` so the cursor follows the control's enabled state.
    func pointingHandCursor(when interactive: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(interactive: interactive))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(isEnabled && interactive ? .link : .default)
        } else {
            content.background(CursorRegion(enabled: isEnabled && interactive))
        }
    }
}

/// Cursor rectangles let AppKit restore the cursor on exit, removal and scrolling
/// without changing the global cursor stack or intercepting clicks.
private struct CursorRegion: NSViewRepresentable {
    let enabled: Bool

    func makeNSView(context: Context) -> CursorView {
        let view = CursorView()
        view.enabled = enabled
        return view
    }

    func updateNSView(_ view: CursorView, context: Context) {
        guard view.enabled != enabled else { return }
        view.enabled = enabled
        view.window?.invalidateCursorRects(for: view)
    }

    final class CursorView: NSView {
        var enabled = false

        override func resetCursorRects() {
            super.resetCursorRects()
            if enabled {
                addCursorRect(visibleRect, cursor: .pointingHand)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
