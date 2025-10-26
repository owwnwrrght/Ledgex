import SwiftUI
import UIKit

/// Bridges the hosting SwiftUI view's `UIWindow` into Swift code that requires a presentation anchor.
struct WindowAccessor: UIViewRepresentable {
    let onWindowResolved: @MainActor (UIWindow?) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = WindowCaptureView()
        view.onWindowResolved = { window in
            Task { @MainActor in
                onWindowResolved(window)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // No-op: window delivery handled via `didMoveToWindow`.
    }
}

private final class WindowCaptureView: UIView {
    var onWindowResolved: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowResolved?(window)
    }
}
