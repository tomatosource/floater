import AppKit

let handleSize: CGFloat = 22
let minWidth: CGFloat = 60

// MARK: - Window

final class FloatWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Image view (click to focus, drag to move)

final class ImageView: NSView {
    var image: NSImage

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
}

// MARK: - Corner resize handle (keeps aspect ratio, top-left anchored)

final class ResizeHandle: NSView {
    let aspect: CGFloat
    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero

    init(aspect: CGFloat) {
        self.aspect = aspect
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        // Dark triangle backing so it's visible on any image.
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: b.maxX, y: b.minY))
        tri.line(to: NSPoint(x: b.maxX, y: b.maxY))
        tri.line(to: NSPoint(x: b.minX, y: b.minY))
        tri.close()
        NSColor.black.withAlphaComponent(0.55).setFill()
        tri.fill()

        // Grip lines.
        NSColor.white.withAlphaComponent(0.9).setStroke()
        for inset in stride(from: CGFloat(5), through: 15, by: 5) {
            let line = NSBezierPath()
            line.lineWidth = 1.5
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: b.maxX - 3, y: b.minY + inset))
            line.line(to: NSPoint(x: b.minX + inset, y: b.minY + 3))
            line.stroke()
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
        let dx = now.x - startMouse.x
        let dy = startMouse.y - now.y // dragging down grows
        let w = max(minWidth, max(startFrame.width + dx, (startFrame.height + dy) * aspect))
        let h = w / aspect
        let top = startFrame.maxY
        window.setFrame(NSRect(x: startFrame.minX, y: top - h, width: w, height: h), display: true)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        closeOtherInstances()
        setupMenu()
        showClipboard()
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

        window?.close()

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

        let handle = ResizeHandle(aspect: aspect)
        handle.frame = NSRect(x: size.width - handleSize, y: 0, width: handleSize, height: handleSize)
        handle.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(handle)

        w.contentView = content
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
