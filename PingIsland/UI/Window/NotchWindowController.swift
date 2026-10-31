//
//  NotchWindowController.swift
//  PingIsland
//
//  Controls the notch window positioning and lifecycle
//

import AppKit
import Combine
import SwiftUI

class NotchWindowController: NSWindowController {
    let viewModel: NotchViewModel
    private let presentationWindowFrame: NSRect
    private var cancellables = Set<AnyCancellable>()

    init(
        screen: NSScreen,
        viewModel: NotchViewModel,
        sessionMonitor: SessionMonitor,
        performBootAnimation: Bool
    ) {
        self.viewModel = viewModel

        let screenFrame = screen.frame

        // Mac Island uses a localized compositor surface around the actual
        // capsule. Keeping a screen-wide, 750pt-high transparent panel at a
        // system window level makes Notification Center's material sample black.
        let windowFrame =
            MacIslandProductPolicy.monitorOnly
            ? MacIslandPresentationPolicy.dockedWindowFrame(in: screenFrame)
            : NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.maxY - 750,
                width: screenFrame.width,
                height: 750
            )
        self.presentationWindowFrame = windowFrame

        // Create the window
        let notchWindow = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: notchWindow)

        // Create the SwiftUI view with pass-through hosting
        let hostingController = NotchViewController(
            viewModel: viewModel,
            sessionMonitor: sessionMonitor
        )
        notchWindow.contentViewController = hostingController

        notchWindow.setFrame(windowFrame, display: true)

        // Dynamically toggle mouse event handling based on notch state:
        // - Closed: ignoresMouseEvents = true (clicks pass through to menu bar/apps)
        // - Opened: ignoresMouseEvents = false (buttons inside panel work)
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$openReason
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$isFullscreenEdgeRevealActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$isFullscreenBrowserHiddenActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$isIdleAutoHiddenActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$isQuietBackgroundPresentationActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$presentationMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$isFullscreenBrowserHiddenActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$isIdleAutoHiddenActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        EnergyGovernor.shared.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] mode in
                guard let self, let notchWindow, let viewModel else { return }
                viewModel.updateQuietBackgroundPresentationState(isActive: mode == .quietBackground)
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        // Start with ignoring mouse events (closed state)
        notchWindow.ignoresMouseEvents = true
        updateWindowPresentation(window: notchWindow, viewModel: viewModel)

        // Perform boot animation after a brief delay
        if performBootAnimation {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.viewModel.performBootAnimation()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateWindowPresentation(window: NotchPanel, viewModel: NotchViewModel) {
        let shouldHideWindow = viewModel.shouldHideWindowPresentation

        if shouldHideWindow {
            window.ignoresMouseEvents = true
            if window.isVisible {
                window.orderOut(nil)
            }
            return
        }

        if window.frame != presentationWindowFrame {
            window.setFrame(presentationWindowFrame, display: true)
        }

        if !window.isVisible {
            window.orderFront(nil)
        }

        switch viewModel.status {
        case .opened:
            window.ignoresMouseEvents = false
            if MacIslandPresentationPolicy.shouldBecomeKey(openReason: viewModel.openReason) {
                NSApp.activate(ignoringOtherApps: false)
                window.makeKey()
            } else if window.isKeyWindow {
                window.resignKey()
            }
        case .closed, .popping:
            window.ignoresMouseEvents = true
            if window.isKeyWindow {
                window.resignKey()
            }
        }
    }
}
