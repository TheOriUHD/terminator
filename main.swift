import Cocoa

func ownerUID(_ pid: pid_t) -> uid_t? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
    return info.kp_eproc.e_ucred.cr_uid
}

// Height needed to wrap `text` in a label of the given width (labels have a couple of points of inset each side).
func wrappedHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
    let rect = (text as NSString).boundingRect(with: NSSize(width: width - 4, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading],
                                               attributes: [.font: font],
                                               context: nil)
    return ceil(rect.height) + 4
}

// Tab / Shift-Tab / Space / Esc handling shared by the controls in the dialog's key loop.
// Returns false for any other key so the caller can pass it on.
func handleKeyboardNavigation(_ event: NSEvent, in view: NSView, activate: () -> Void) -> Bool {
    switch event.keyCode {
    case 49:  // Space
        if !event.isARepeat { activate() }
    case 48:  // Tab / Shift-Tab
        if event.modifierFlags.contains(.shift) {
            view.window?.selectPreviousKeyView(view)
        } else {
            view.window?.selectNextKeyView(view)
        }
    case 53:  // Esc
        view.window?.cancelOperation(nil)
    default:
        return false
    }
    return true
}

// Flipped so subviews are laid out from the top.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// The dialog window. Esc cancels, like the Cancel button does.
class ConfirmPanel: NSPanel {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

// Push button that Tab can always reach, whatever the system's keyboard-navigation setting is.
class TabbableButton: NSButton {
    var onClick: (() -> Void)?

    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled }

    @objc func clicked() {
        onClick?()
    }

    override func keyDown(with event: NSEvent) {
        if !handleKeyboardNavigation(event, in: self, activate: { self.performClick(nil) }) {
            super.keyDown(with: event)
        }
    }
}

// One row of the list: checkbox, icon and name. Clicking anywhere on the row toggles the checkbox.
// The row itself takes keyboard focus: Tab / Shift-Tab move between rows and Space toggles the focused one.
class AppRow: NSView {
    let app: NSRunningApplication
    var onChange: (() -> Void)?
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    var isChecked: Bool {
        get { checkbox.state == .on }
        set { checkbox.state = newValue ? .on : .off }
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 4, dy: 3) }

    init(app: NSRunningApplication, name: String, frame: NSRect) {
        self.app = app
        super.init(frame: frame)
        autoresizingMask = [.width]
        focusRingType = .exterior

        checkbox.state = .on  // everything starts out selected
        checkbox.refusesFirstResponder = true  // the row takes the focus, not the checkbox inside it
        checkbox.target = self
        checkbox.action = #selector(toggled)
        checkbox.setAccessibilityLabel(name)
        checkbox.sizeToFit()
        checkbox.frame.origin = NSPoint(x: 10, y: (frame.height - checkbox.frame.height) / 2)
        addSubview(checkbox)

        let icon = NSImageView(frame: NSRect(x: 36, y: (frame.height - 22) / 2, width: 22, height: 22))
        icon.image = app.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        let label = NSTextField(labelWithString: name)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 66, y: (frame.height - 17) / 2, width: frame.width - 76, height: 17)
        label.autoresizingMask = [.width]
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggled() {
        window?.makeFirstResponder(self)  // clicking a row also moves keyboard focus to it
        onChange?()
    }

    override func mouseDown(with event: NSEvent) {
        checkbox.performClick(nil)
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 5, yRadius: 5).fill()
    }

    override func becomeFirstResponder() -> Bool {
        _ = scrollToVisible(bounds)  // keep the focused row on screen when tabbing through a long list
        return super.becomeFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if !handleKeyboardNavigation(event, in: self, activate: { self.checkbox.performClick(nil) }) {
            super.keyDown(with: event)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myUID = getuid()
        let myBID = Bundle.main.bundleIdentifier
        let myExec = Bundle.main.executableURL

        let systemApps: Set<String> = [
            "com.apple.finder",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.apple.systemuiserver",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.WindowManager",
            "com.apple.backgroundtaskmanagement.agent",
        ]

        // Everything Terminator is allowed to kill: your own regular apps, minus itself and the system ones.
        let isTarget: (NSRunningApplication) -> Bool = { app in
            guard app.activationPolicy == .regular else { return false }
            guard app.processIdentifier != myPID else { return false }
            if let mb = myBID, let ab = app.bundleIdentifier, mb == ab { return false }
            if let me = myExec, let ae = app.executableURL, me == ae { return false }
            guard let uid = ownerUID(app.processIdentifier), uid == myUID else { return false }
            if let bid = app.bundleIdentifier, systemApps.contains(bid) { return false }
            return true
        }

        func displayName(_ app: NSRunningApplication) -> String {
            app.localizedName ?? app.bundleIdentifier ?? "PID \(app.processIdentifier)"
        }

        let candidates = NSWorkspace.shared.runningApplications
            .filter(isTarget)
            .sorted { displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending }

        // Bring the app (and its dialog) to the front so the confirmation is visible.
        NSApp.activate(ignoringOtherApps: true)

        guard !candidates.isEmpty else {
            let none = NSAlert()
            none.messageText = "Terminator"
            none.informativeText = "There are no applications to terminate."
            none.runModal()
            NSApp.terminate(nil)
            return
        }

        // Dialog geometry: a 64pt icon on the left, everything else in the text column beside it.
        let panelWidth: CGFloat = 470
        let margin: CGFloat = 24
        let textX = margin + 64 + 16
        let textWidth = panelWidth - textX - margin

        // Scrollable checklist of the running apps, like the Force Quit window. All checked by default.
        let rowHeight: CGFloat = 30
        let listHeight = CGFloat(min(candidates.count, 8)) * rowHeight + 4
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: textWidth, height: listHeight))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        let list = FlippedView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: CGFloat(candidates.count) * rowHeight))
        list.autoresizingMask = [.width]
        let rows = candidates.enumerated().map { index, app in
            AppRow(app: app, name: displayName(app),
                   frame: NSRect(x: 0, y: CGFloat(index) * rowHeight, width: list.frame.width, height: rowHeight))
        }
        rows.forEach { list.addSubview($0) }
        scroll.documentView = list

        // The buttons are our own (not an NSAlert's) so that Tab can reach every one of them.
        func makeButton(_ title: String) -> TabbableButton {
            let button = TabbableButton(title: title, target: nil, action: nil)
            button.target = button
            button.action = #selector(TabbableButton.clicked)
            return button
        }
        let selectAllButton = makeButton("Deselect All")
        selectAllButton.controlSize = .small
        selectAllButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let cancelButton = makeButton("Cancel")
        let terminateButton = makeButton("Terminate")
        // Make Cancel the default (Return) so an accidental keypress does not
        // trigger the destructive action; terminating requires an explicit click.
        cancelButton.keyEquivalent = "\r"

        // Keep the buttons in step with the checkboxes: show the count, disable Terminate when nothing is
        // checked, and make the toggle offer whichever of select-all / deselect-all applies.
        let refreshButtons = {
            let n = rows.filter(\.isChecked).count
            terminateButton.title = n == 0 ? "Terminate" : "Terminate \(n) \(n == 1 ? "Application" : "Applications")"
            terminateButton.isEnabled = n > 0
            selectAllButton.title = n == rows.count ? "Deselect All" : "Select All"
        }
        rows.forEach { $0.onChange = refreshButtons }
        selectAllButton.onClick = {
            let allChecked = rows.allSatisfy(\.isChecked)
            rows.forEach { $0.isChecked = !allChecked }
            refreshButtons()
        }
        refreshButtons()

        cancelButton.onClick = { NSApp.stopModal(withCode: .cancel) }
        terminateButton.onClick = { NSApp.stopModal(withCode: .OK) }

        // Lay everything out top to bottom.
        let titleText = "Terminate the selected applications?"
        let titleFont = NSFont.boldSystemFont(ofSize: 13)
        let infoText = "The checked applications will be force quit. Any unsaved work in them will be lost. This action cannot be undone."
        let infoFont = NSFont.systemFont(ofSize: 11)

        cancelButton.sizeToFit()
        terminateButton.sizeToFit()
        cancelButton.frame.size.width = max(cancelButton.frame.width, 80)
        let buttonHeight = max(cancelButton.frame.height, terminateButton.frame.height)

        let titleY: CGFloat = 20
        let titleHeight = wrappedHeight(titleText, font: titleFont, width: textWidth)
        let infoY = titleY + titleHeight + 6
        let infoHeight = wrappedHeight(infoText, font: infoFont, width: textWidth)
        let selectAllY = infoY + infoHeight + 14
        let listY = selectAllY + 21 + 6
        let buttonsY = listY + listHeight + 20
        let contentHeight = buttonsY + buttonHeight + 20

        func makeLabel(_ text: String, font: NSFont, y: CGFloat, height: CGFloat) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = font
            label.isSelectable = false
            label.frame = NSRect(x: textX, y: y, width: textWidth, height: height)
            return label
        }

        let icon = NSImageView(frame: NSRect(x: margin, y: titleY, width: 64, height: 64))
        icon.image = NSImage(named: NSImage.cautionName)

        selectAllButton.frame = NSRect(x: textX, y: selectAllY, width: 110, height: 21)
        scroll.frame.origin = NSPoint(x: textX, y: listY)
        terminateButton.frame.origin = NSPoint(x: panelWidth - margin - terminateButton.frame.width, y: buttonsY)
        cancelButton.frame.origin = NSPoint(x: terminateButton.frame.minX - 12 - cancelButton.frame.width, y: buttonsY)

        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: contentHeight))
        content.addSubview(icon)
        content.addSubview(makeLabel(titleText, font: titleFont, y: titleY, height: titleHeight))
        content.addSubview(makeLabel(infoText, font: infoFont, y: infoY, height: infoHeight))
        content.addSubview(selectAllButton)
        content.addSubview(scroll)
        content.addSubview(cancelButton)
        content.addSubview(terminateButton)

        let panel = ConfirmPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: contentHeight),
                                 styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Terminator"
        panel.isReleasedWhenClosed = false
        let windowButtons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        windowButtons.forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.contentView = content
        panel.defaultButtonCell = cancelButton.cell as? NSButtonCell
        panel.onCancel = { NSApp.stopModal(withCode: .cancel) }

        // Tab order: all the buttons first (Select All, then Cancel and Terminate), then every row top to
        // bottom, then round again to the buttons.
        var tabOrder: [NSView] = [selectAllButton, cancelButton, terminateButton]
        tabOrder += rows.map { $0 as NSView }
        for (i, view) in tabOrder.enumerated() {
            view.nextKeyView = tabOrder[(i + 1) % tabOrder.count]
        }
        panel.autorecalculatesKeyViewLoop = false
        panel.initialFirstResponder = selectAllButton
        panel.makeFirstResponder(selectAllButton)

        // Ask for confirmation before terminating anything.
        panel.center()
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        guard response == .OK else {
            NSApp.terminate(nil)
            return
        }

        // Only the apps still checked in the list are targeted.
        let selectedPIDs = Set(rows.filter(\.isChecked).map { $0.app.processIdentifier })

        DispatchQueue.global().async {
            var killedPIDs = Set<pid_t>()

            while true {
                var killed = false
                for app in NSWorkspace.shared.runningApplications {
                    guard selectedPIDs.contains(app.processIdentifier), isTarget(app) else { continue }

                    kill(app.processIdentifier, SIGKILL)
                    killedPIDs.insert(app.processIdentifier)
                    killed = true
                }
                if !killed { break }
                Thread.sleep(forTimeInterval: 0.3)
            }

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Terminator"
                alert.informativeText = "Terminated \(killedPIDs.count) application(s)."
                alert.runModal()
                NSApp.terminate(nil)
            }
        }
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
