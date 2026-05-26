//
//  WindowAccessor.swift
//  CalWidget
//
//  Created by Codex.
//

import AppKit
import ObjectiveC
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        TrackingView(configure: configure)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op: configuration runs once when the window first becomes available.
    }
}

private final class TrackingView: NSView {
    private let configure: (NSWindow) -> Void
    private var didConfigure = false

    init(configure: @escaping (NSWindow) -> Void) {
        self.configure = configure
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !didConfigure, let window else {
            return
        }
        didConfigure = true
        configure(window)
    }
}

enum WindowStyleCoordinator {
    private static let fixedWidth: CGFloat = 320
    private static let observerKey = ObserverKey()

    private final class ObserverKey {}

    static func apply(to window: NSWindow) {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame

        window.styleMask = [.borderless, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.level = .normal
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        window.setContentSize(NSSize(width: fixedWidth, height: max(window.frame.height, 720)))
        window.minSize = NSSize(width: fixedWidth, height: 680)
        window.maxSize = NSSize(width: fixedWidth, height: 10_000)

        guard let visibleFrame else {
            return
        }

        let targetFrame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: fixedWidth,
            height: visibleFrame.height - 1
        )

        if abs(window.frame.width - fixedWidth) > 0.5 || abs(window.frame.height - visibleFrame.height) > 0.5 {
            window.setFrame(targetFrame, display: true, animate: false)
        }

        installWindowObserversIfNeeded(for: window)
        sendWindowBack(window)
    }

    private static func installWindowObserversIfNeeded(for window: NSWindow) {
        let key = Unmanaged.passUnretained(observerKey).toOpaque()
        if objc_getAssociatedObject(window, key) != nil {
            return
        }

        let observer = WindowOrderObserver(window: window)
        objc_setAssociatedObject(window, key, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    // Sent twice because macOS sometimes re-orders the window forward after the initial call
    // (e.g. when the WindowGroup is restored at launch). A short delayed second call wins that race.
    private static func sendWindowBack(_ window: NSWindow) {
        DispatchQueue.main.async {
            window.orderBack(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            window.orderBack(nil)
        }
    }
}

private final class WindowOrderObserver {
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    init(window: NSWindow) {
        self.window = window

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.sendWindowBack()
            }
        )
    }

    deinit {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspaceCenter.removeObserver(observer)
        }
    }

    private func sendWindowBack() {
        guard let window else {
            return
        }

        DispatchQueue.main.async {
            window.orderBack(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            window.orderBack(nil)
        }
    }
}
