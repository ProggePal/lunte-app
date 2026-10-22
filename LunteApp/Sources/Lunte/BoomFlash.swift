import AppKit
import SwiftUI

/// The Boom moment on screen: a one-second comic "💥 BOOM" over everything. Clicks pass through.
@MainActor
enum BoomFlash {
    private static var panel: NSPanel?

    static func show(_ word: String = "BOOM") {
        guard let screen = NSScreen.main else { return }
        panel?.close()
        let size = NSSize(width: 900, height: 260)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: FlashView(word: word))
        p.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        p.orderFrontRegardless()
        panel = p
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }) {
                MainActor.assumeIsolated {
                    p.close()
                    if panel === p { panel = nil }
                }
            }
        }
    }
}

private struct FlashView: View {
    let word: String
    @State private var popped = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        Text("💥 " + word)
            .font(.system(size: 76, weight: .black, design: .rounded))
            .foregroundStyle(.yellow)
            .padding(.horizontal, 32).padding(.vertical, 14)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 28))
            .fixedSize()
            .scaleEffect(popped ? 1 : 0.3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { popped = true } }
    }
}
