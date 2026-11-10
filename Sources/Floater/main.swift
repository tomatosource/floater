import AppKit

let handleSize: CGFloat = 22
let minWidth: CGFloat = 80
let buttonSize: CGFloat = 24

// MARK: - Window

final class FloatWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Image view (click to focus, drag to move, hover reveals controls)

final class ImageView: NSView {
    var image: NSImage
    var hoverControls: [NSView] = []

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.performDrag(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }

    func setHover(_ on: Bool) {
        hoverControls.forEach { $0.isHidden = !on }
    }
}

// MARK: - Corner resize handle (keeps aspect ratio, opposite corner anchored)

enum Corner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isRight: Bool { self == .topRight || self == .bottomRight }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

final class ResizeHandle: NSView {
    let aspect: CGFloat
    let corner: Corner
    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero

    init(aspect: CGFloat, corner: Corner) {
        self.aspect = aspect
        self.corner = corner
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        var cursor = NSCursor.crosshair
        if #available(macOS 15, *) {
            let pos: NSCursor.FrameResizePosition = switch corner {
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            }
            cursor = .frameResize(position: pos, directions: .all)
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        // Draw a bottom-right grip, mirrored into whichever corner this is.
        let t = NSAffineTransform()
        if !corner.isRight { t.translateX(by: b.width, yBy: 0); t.scaleX(by: -1, yBy: 1) }
        if corner.isTop { t.translateX(by: 0, yBy: b.height); t.scaleX(by: 1, yBy: -1) }
        t.concat()

        // Three diagonal lines; dark outline under white so they show on any image.
        for (color, width) in [(NSColor.black.withAlphaComponent(0.6), 3.5), (NSColor.white, 1.5)] {
            color.setStroke()
            for inset in stride(from: CGFloat(6), through: 16, by: 5) {
                let line = NSBezierPath()
                line.lineWidth = width
                line.lineCapStyle = .round
                line.move(to: NSPoint(x: b.maxX - 3, y: b.minY + inset))
                line.line(to: NSPoint(x: b.minX + inset, y: b.minY + 3))
                line.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        startFrame = window?.frame ?? .zero
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = (now.x - startMouse.x) * (corner.isRight ? 1 : -1)
        let dy = (now.y - startMouse.y) * (corner.isTop ? 1 : -1)
        let w = max(minWidth, max(startFrame.width + dx, (startFrame.height + dy) * aspect))
        let h = w / aspect
        let x = corner.isRight ? startFrame.minX : startFrame.maxX - w
        let y = corner.isTop ? startFrame.minY : startFrame.maxY - h
        window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }
}

// MARK: - Ghost buttons (shown on hover)

final class GhostButton: NSView {
    var symbolName: String
    let action: (GhostButton) -> Void

    init(symbol: String, action: @escaping (GhostButton) -> Void) {
        self.symbolName = symbol
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        NSColor.black.withAlphaComponent(0.45).setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.7).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let s = symbol.size
            symbol.draw(in: NSRect(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2,
                                   width: s.width, height: s.height))
        }
    }

    override func mouseDown(with event: NSEvent) { action(self) }

    // Briefly swap the icon to confirm an action.
    func flash(_ symbol: String) {
        let original = symbolName
        symbolName = symbol
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.symbolName = original
            self?.needsDisplay = true
        }
    }
}

// MARK: - Saved state (last image + window frame, for `--restore` relaunches)

enum SavedState {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Floater")
    static let imageURL = dir.appendingPathComponent("last.png")
    static let frameKey = "lastFrame"

    static func save(image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: imageURL)
    }

    static func save(frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: frameKey)
    }

    static func load() -> (image: NSImage, frame: NSRect)? {
        guard let image = NSImage(contentsOf: imageURL),
              let frame = UserDefaults.standard.string(forKey: frameKey).map(NSRectFromString),
              frame.width > 0, frame.height > 0 else { return nil }
        return (image, frame)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        closeOtherInstances()
        setupMenu()
        if CommandLine.arguments.contains("--restore"), let state = SavedState.load() {
            show(image: state.image, frame: state.frame)
        } else {
            showClipboard()
        }
    }

    // Clicking the Dock icon / `open`-ing again while running: refresh from clipboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showClipboard()
        return false
    }

    func closeOtherInstances() {
        let me = NSRunningApplication.current
        guard let id = Bundle.main.bundleIdentifier else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: id)
        where app.processIdentifier != me.processIdentifier {
            app.terminate()
        }
    }

    func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Floater", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    func showClipboard() {
        guard let image = NSImage(pasteboard: .general), image.isValid else {
            notify("No image on clipboard")
            NSApp.terminate(nil)
            return
        }

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main!
        let visible = screen.visibleFrame

        // Natural size in points: pixels / screen scale (falls back to NSImage size).
        var size = image.size
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            size = NSSize(width: CGFloat(rep.pixelsWide) / screen.backingScaleFactor,
                          height: CGFloat(rep.pixelsHigh) / screen.backingScaleFactor)
        }
        let aspect = size.width / size.height
        let maxW = visible.width * 0.8, maxH = visible.height * 0.8
        if size.width > maxW { size = NSSize(width: maxW, height: maxW / aspect) }
        if size.height > maxH { size = NSSize(width: maxH * aspect, height: maxH) }
        if size.width < minWidth { size = NSSize(width: minWidth, height: minWidth / aspect) }

        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                           width: size.width, height: size.height)
        show(image: image, frame: frame)
    }

    func show(image: NSImage, frame: NSRect) {
        window?.close()
        SavedState.save(image: image)
        SavedState.save(frame: frame)

        let size = frame.size
        let aspect = size.width / size.height
        let w = FloatWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .floating
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isReleasedWhenClosed = false

        let content = ImageView(image: image)
        content.frame = NSRect(origin: .zero, size: size)
        content.autoresizingMask = [.width, .height]

        for corner in Corner.allCases {
            let handle = ResizeHandle(aspect: aspect, corner: corner)
            handle.frame = NSRect(x: corner.isRight ? size.width - handleSize : 0,
                                  y: corner.isTop ? size.height - handleSize : 0,
                                  width: handleSize, height: handleSize)
            handle.autoresizingMask = [corner.isRight ? .minXMargin : .maxXMargin,
                                       corner.isTop ? .minYMargin : .maxYMargin]
            content.addSubview(handle)
            if corner != .bottomRight { content.hoverControls.append(handle) }
        }

        let opacity = GhostButton(symbol: "circle.lefthalf.filled") { b in
            guard let window = b.window else { return }
            window.alphaValue = window.alphaValue < 1 ? 1 : 0.25
        }
        let copy = GhostButton(symbol: "doc.on.doc") { b in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            b.flash("checkmark")
        }
        // Right-to-left from just inside the top-right resize handle.
        for (i, button) in [opacity, copy].enumerated() {
            let x = size.width - handleSize - 4 - CGFloat(i + 1) * buttonSize - CGFloat(i) * 6
            button.frame = NSRect(x: x, y: size.height - buttonSize - 6, width: buttonSize, height: buttonSize)
            button.autoresizingMask = [.minXMargin, .minYMargin]
            content.addSubview(button)
            content.hoverControls.append(button)
        }

        let mouseInside = NSMouseInRect(NSEvent.mouseLocation, frame, false)
        content.setHover(mouseInside)

        w.contentView = content
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { n in
                if let win = n.object as? NSWindow { SavedState.save(frame: win.frame) }
            }
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    func notify(_ message: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(message)\" with title \"Floater\""]
        try? p.run()
        p.waitUntilExit()
    }
}

let app = NSApplication.shared
// Accessory: no Cmd+Tab entry, no menu bar takeover. Pin the .app in the Dock to launch it.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
