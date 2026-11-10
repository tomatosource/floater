import AppKit

let handleSize: CGFloat = 22
let hotCornerSize: CGFloat = 14
let minWidth: CGFloat = 80
let buttonSize: CGFloat = 32
let buttonInset: CGFloat = 8
let bigMargin: CGFloat = 20     // A (big) and B's default keep this clear of the screen edges
let smallFraction: CGFloat = 0.3 // B's default: longer side as a fraction of the screen's longer side

// MARK: - Window

final class FloatWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Image view (click to focus, drag to move, hover reveals controls)

final class ImageView: NSView {
    var image: NSImage
    var hoverControls: [NSView] = []
    var imageOpacity: CGFloat = 1 {
        didSet { needsDisplay = true; window?.invalidateShadow() }
    }

    // Set for animated GIFs: the rep whose current frame is drawn and advanced on a timer.
    private var animatedRep: NSBitmapImageRep?
    private var frameCount = 1

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        if let rep = image.representations.first as? NSBitmapImageRep,
           let count = rep.value(forProperty: .frameCount) as? Int, count > 1 {
            animatedRep = rep
            frameCount = count
            scheduleNextFrame()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if let rep = animatedRep {
            rep.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: imageOpacity,
                     respectFlipped: true, hints: nil)
        } else {
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: imageOpacity)
        }
    }

    private func scheduleNextFrame() {
        guard let rep = animatedRep else { return }
        // Like browsers, treat near-zero frame delays as 0.1s.
        var delay = (rep.value(forProperty: .currentFrameDuration) as? Double) ?? 0.1
        if delay < 0.02 { delay = 0.1 }
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            // Stop once the window has closed (a new image replaces this view).
            guard let self, self.window != nil, let rep = self.animatedRep else { return }
            let current = (rep.value(forProperty: .currentFrame) as? Int) ?? 0
            rep.setProperty(.currentFrame, withValue: (current + 1) % self.frameCount)
            self.needsDisplay = true
            self.window?.invalidateShadow()
            self.scheduleNextFrame()
        }
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

// MARK: - Corner resize handles (keep aspect ratio, opposite corner anchored)

enum Corner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isRight: Bool { self == .topRight || self == .bottomRight }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

// Only the bottom-right handle draws a grip; the others are invisible hot zones with a resize cursor.

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
        // NSCursor.frameResize needs the macOS 15 SDK (Swift 6 / Xcode 16+);
        // older toolchains (e.g. Xcode 14) fall back to the crosshair.
        #if compiler(>=6.0)
        if #available(macOS 15, *) {
            let pos: NSCursor.FrameResizePosition = switch corner {
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            }
            cursor = .frameResize(position: pos, directions: .all)
        }
        #endif
        addCursorRect(bounds, cursor: cursor)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard corner == .bottomRight else { return }
        let b = bounds
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

// MARK: - Icons (Lucide, ISC license — https://lucide.dev)

enum Icon {
    static let ghost = #"<path d="M15 10v1"/><path d="M7.528 20.472a1.6 1.6 0 012.277 0l1.057 1.056a1.6 1.6 0 002.276 0l1.057-1.056a1.6 1.6 0 012.277 0l1.114 1.114a1.4 1.4 0 002.414-1V10a8 8 0 00-16 0v10.586a1.4 1.4 0 002.414 1z"/><path d="M9 10v1"/>"#
    static let copy = #"<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>"#
    static let check = #"<path d="M20 6 9 17l-5-5"/>"#
    static let eraser = #"<path d="M21 21H8a2 2 0 0 1-1.42-.587l-3.994-3.999a2 2 0 0 1 0-2.828l10-10a2 2 0 0 1 2.828 0l5.999 6a2 2 0 0 1 0 2.828L12.834 21"/><path d="m5.082 11.09 8.828 8.828"/>"#

    static func image(_ body: String, size: CGFloat) -> NSImage? {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">"# + body + "</svg>"
        let image = NSImage(data: Data(svg.utf8))
        image?.size = NSSize(width: size, height: size)
        return image
    }
}

// MARK: - Ghost buttons (shown on hover)

// Shows an icon, or a letter when `icon` is nil. With `doubleAction`, a single click waits out the
// double-click interval so a double-click doesn't fire the single-click action first. A triple-click
// fires `doubleAction` then `tripleAction`.
final class GhostButton: NSView {
    var icon: String? { didSet { needsDisplay = true } }
    var label: String? { didSet { needsDisplay = true } }
    var iconAlpha: CGFloat = 1 { didSet { needsDisplay = true } }
    let action: (GhostButton) -> Void
    var doubleAction: ((GhostButton) -> Void)?
    var tripleAction: ((GhostButton) -> Void)?
    private var pendingClick: DispatchWorkItem?

    init(icon: String?, label: String? = nil, tooltip: String, action: @escaping (GhostButton) -> Void) {
        self.icon = icon
        self.label = label
        self.action = action
        super.init(frame: .zero)
        toolTip = tooltip
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        NSColor.black.withAlphaComponent(0.5).setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.6).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        if let icon {
            let side: CGFloat = 18
            Icon.image(icon, size: side)?.draw(
                in: NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side),
                from: .zero, operation: .sourceOver, fraction: iconAlpha)
        } else if let label {
            let text = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(iconAlpha),
            ])
            let s = text.size()
            text.draw(at: NSPoint(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2))
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let doubleAction else { return action(self) }
        pendingClick?.cancel()
        if event.clickCount >= 3, let tripleAction { return tripleAction(self) }
        if event.clickCount >= 2 { return doubleAction(self) }
        let click = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.action(self)
        }
        pendingClick = click
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: click)
    }

    // Briefly swap the icon to confirm an action.
    func flash(_ temporary: String) {
        let original = icon
        icon = temporary
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.icon = original }
    }
}

// Saved window frames (the B button), kept across launches.
enum Slots {
    static func key(_ name: String) -> String { "slot\(name)" }

    static func load(_ name: String) -> NSRect? {
        guard let frame = UserDefaults.standard.string(forKey: key(name)).map(NSRectFromString),
              frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    static func save(_ name: String, frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: key(name))
    }

    static func clear(_ name: String) {
        UserDefaults.standard.removeObject(forKey: key(name))
    }
}

// MARK: - Random photos (Lorem Picsum: random Unsplash photos, free to use, no API key)

enum RandomPhoto {
    // Redirects to a random photo at this size.
    static let url = URL(string: "https://picsum.photos/1600/1067")!

    // Calls back on the main queue.
    static func fetch(completion: @escaping (NSImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let image = ok ? data.flatMap(NSImage.init(data:)) : nil
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }
}

// MARK: - GIFs (kept as their original bytes so they stay animated when saved and copied)

let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")

// GIF bytes on the pasteboard: copied GIF data (e.g. from a browser), or a copied .gif file (Finder).
func pasteboardGIF(_ pb: NSPasteboard) -> Data? {
    if let data = pb.data(forType: gifType) { return data }
    let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    guard let url = urls?.first, url.pathExtension.lowercased() == "gif" else { return nil }
    return try? Data(contentsOf: url)
}

// MARK: - Saved state (last image + window frame, for `--restore` relaunches)

enum SavedState {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Floater")
    static let imageURL = dir.appendingPathComponent("last.png")
    static let gifURL = dir.appendingPathComponent("last.gif")
    static let frameKey = "lastFrame"

    // GIFs are saved as last.gif, anything else as last.png; the other file is removed.
    static func save(image: NSImage, gif: Data?) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let gif {
            try? gif.write(to: gifURL)
            try? FileManager.default.removeItem(at: imageURL)
            return
        }
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: imageURL)
        try? FileManager.default.removeItem(at: gifURL)
    }

    static func save(frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: frameKey)
    }

    // Uses whichever of last.png / last.gif is newer, in case something outside the app wrote one.
    static func load() -> (image: NSImage, gif: Data?, frame: NSRect)? {
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        let gif = modified(gifURL) > modified(imageURL) ? try? Data(contentsOf: gifURL) : nil
        guard let image = gif.flatMap(NSImage.init(data:)) ?? NSImage(contentsOf: imageURL),
              let frame = UserDefaults.standard.string(forKey: frameKey).map(NSRectFromString),
              frame.width > 0, frame.height > 0 else { return nil }
        return (image, gif, frame)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        closeOtherInstances()
        setupMenu()
        if CommandLine.arguments.contains("--restore"), let state = SavedState.load() {
            show(image: state.image, gif: state.gif, frame: state.frame)
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
        let gif = pasteboardGIF(.general)
        guard let image = gif.flatMap(NSImage.init(data:)) ?? NSImage(pasteboard: .general), image.isValid else {
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
        show(image: image, gif: gif, frame: frame)
    }

    func show(image: NSImage, gif: Data?, frame: NSRect) {
        window?.close()
        SavedState.save(image: image, gif: gif)
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

        // Added before the buttons so the buttons win where they overlap.
        for corner in Corner.allCases {
            let side = corner == .bottomRight ? handleSize : hotCornerSize
            let handle = ResizeHandle(aspect: aspect, corner: corner)
            handle.frame = NSRect(x: corner.isRight ? size.width - side : 0,
                                  y: corner.isTop ? size.height - side : 0,
                                  width: side, height: side)
            handle.autoresizingMask = [corner.isRight ? .minXMargin : .maxXMargin,
                                       corner.isTop ? .minYMargin : .maxYMargin]
            content.addSubview(handle)
        }

        // Only the image fades, so grips and buttons stay fully visible.
        let ghost = GhostButton(icon: Icon.ghost, tooltip: "Toggle transparency") { [unowned content] b in
            content.imageOpacity = content.imageOpacity < 1 ? 1 : 0.4
            b.iconAlpha = content.imageOpacity < 1 ? 0.4 : 1
        }
        let copy = GhostButton(icon: Icon.copy, tooltip: "Copy image") { b in
            let pb = NSPasteboard.general
            pb.clearContents()
            if let gif {
                // GIF bytes for apps that take animation, TIFF (first frame) for the rest.
                pb.declareTypes([gifType, .tiff], owner: nil)
                pb.setData(gif, forType: gifType)
                pb.setData(image.tiffRepresentation, forType: .tiff)
            } else {
                pb.writeObjects([image])
            }
            b.flash(Icon.check)
        }
        // Dimmed while a photo loads; a failed fetch beeps.
        let photo = GhostButton(icon: Icon.eraser, tooltip: "Replace with a random photo") { [weak self, weak w] b in
            guard b.iconAlpha == 1 else { return }
            b.iconAlpha = 0.4
            RandomPhoto.fetch { photo in
                b.iconAlpha = 1
                guard let self, let w, let photo else { NSSound.beep(); return }
                // Same centre and area as the current window, reshaped to the photo's aspect ratio.
                let f = w.frame, a = photo.size.width / photo.size.height
                let nw = (f.width * f.height * a).squareRoot(), nh = nw / a
                self.show(image: photo, gif: nil,
                          frame: NSRect(x: f.midX - nw / 2, y: f.midY - nh / 2, width: nw, height: nh))
            }
        }
        // A: fixed big mode — as large as fits the screen (keeping aspect, bigMargin clear of the edges), centred.
        let a = GhostButton(icon: nil, label: "A", tooltip: "Big") { [weak w] _ in
            guard let w, let screen = w.screen ?? NSScreen.main else { return }
            let area = screen.visibleFrame.insetBy(dx: bigMargin, dy: bigMargin)
            let bw = min(area.width, area.height * aspect), bh = bw / aspect
            w.setFrame(NSRect(x: area.midX - bw / 2, y: area.midY - bh / 2, width: bw, height: bh),
                       display: true, animate: true)
        }
        // B: click snaps to the saved frame, or by default small in the top-right corner (longer side
        // smallFraction of the screen's longer side). Double-click saves, triple-click clears.
        let b = GhostButton(icon: nil, label: "B",
                            tooltip: "Click: snap to B. Double-click: save this position. Triple-click: reset.") { [weak w] _ in
            guard let w, let screen = w.screen ?? NSScreen.main else { return }
            if let saved = Slots.load("B") {
                // Keep the saved centre and width; fit the height to this image's aspect ratio.
                let h = saved.width / aspect
                w.setFrame(NSRect(x: saved.minX, y: saved.midY - h / 2, width: saved.width, height: h),
                           display: true, animate: true)
                return
            }
            let area = screen.visibleFrame.insetBy(dx: bigMargin, dy: bigMargin)
            let long = smallFraction * max(screen.visibleFrame.width, screen.visibleFrame.height)
            let sw = aspect >= 1 ? long : long * aspect, sh = sw / aspect
            w.setFrame(NSRect(x: area.maxX - sw, y: area.maxY - sh, width: sw, height: sh),
                       display: true, animate: true)
        }
        b.doubleAction = { [weak w] b in
            guard let w else { return }
            Slots.save("B", frame: w.frame)
            b.flash(Icon.check)
        }
        b.tripleAction = { b in
            Slots.clear("B")
            b.flash(Icon.check)
        }
        // Right-to-left from the top-right corner: A B photo copy ghost.
        for (i, button) in [ghost, copy, photo, b, a].enumerated() {
            let x = size.width - buttonInset - CGFloat(i + 1) * buttonSize - CGFloat(i) * 6
            button.frame = NSRect(x: x, y: size.height - buttonSize - buttonInset,
                                  width: buttonSize, height: buttonSize)
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
