import AppKit

let hotCornerSize: CGFloat = 14
let minWidth: CGFloat = 80
let buttonSize: CGFloat = 32
let buttonInset: CGFloat = 8
let bigMargin: CGFloat = 20     // big mode and small mode's default keep this clear of the screen edges
let smallFraction: CGFloat = 0.223 // small mode's default: longer side as a fraction of the screen's longer side
let edgeSnap: CGFloat = 60      // a window this close to (or past) a screen edge is anchored to it

// MARK: - Window

final class FloatWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Image view (click to focus, drag to move, double-click to toggle size, hover reveals controls)

final class ImageView: NSView {
    var image: NSImage
    var hoverControls: [NSView] = []
    var onDoubleClick: (() -> Void)?

    // Set for animated GIFs: the rep whose current frame is drawn and advanced on a timer.
    private var animatedRep: NSBitmapImageRep?
    private var frameCount = 1
    private var frameTimer: Timer?
    var isAnimated: Bool { animatedRep != nil }
    // The play/pause button: holds the current frame until resumed.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            frameTimer?.invalidate()
            if !isPaused { scheduleNextFrame() }
        }
    }

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
            rep.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: nil)
        } else {
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private func scheduleNextFrame() {
        guard let rep = animatedRep else { return }
        // Like browsers, treat near-zero frame delays as 0.1s.
        var delay = (rep.value(forProperty: .currentFrameDuration) as? Double) ?? 0.1
        if delay < 0.02 { delay = 0.1 }
        frameTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            // Stop once the window has closed (a new image replaces this view).
            guard let self, self.window != nil, !self.isPaused, let rep = self.animatedRep else { return }
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
        if event.clickCount == 2 { onDoubleClick?(); return }
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

// Invisible hot zones with a resize cursor.

final class ResizeHandle: NSView {
    let aspect: CGFloat
    let corner: Corner
    private var startFrame = NSRect.zero
    private var startMouse = NSPoint.zero
    private var anchor = Anchor(.zero)

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

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        startFrame = window?.frame ?? .zero
        startMouse = NSEvent.mouseLocation
        anchor = Anchor(startFrame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = (now.x - startMouse.x) * (corner.isRight ? 1 : -1)
        let dy = (now.y - startMouse.y) * (corner.isTop ? 1 : -1)
        let w = max(minWidth, max(startFrame.width + dx, (startFrame.height + dy) * aspect))
        let h = w / aspect
        // Edges the window hugs stay put; otherwise the corner opposite the handle does.
        var a = anchor
        if a.x == 0 { a.x = corner.isRight ? -1 : 1 }
        if a.y == 0 { a.y = corner.isTop ? -1 : 1 }
        window.setFrame(a.place(NSSize(width: w, height: h), from: startFrame), display: true)
    }
}

// MARK: - Icons (Lucide, https://lucide.dev, except where noted; license in THIRD_PARTY_LICENSES)

enum Icon {
    static let check = #"<path d="M20 6 9 17l-5-5"/>"#
    static let pause = #"<rect x="14" y="3" width="5" height="18" rx="1"/><rect x="5" y="3" width="5" height="18" rx="1"/>"#
    static let play = #"<path d="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"/>"#
    static let pin = #"<path d="M12 17v5"/><path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/>"#
    static let x = #"<path d="M18 6 6 18"/><path d="m6 6 12 12"/>"#
    // Not Lucide: a screen with a big centred window / a small one in the top-right corner.
    static let big = #"<rect x="2" y="4" width="20" height="16" rx="2"/><rect x="5.5" y="7.5" width="13" height="9" rx="1"/>"#
    static let small = #"<rect x="2" y="4" width="20" height="16" rx="2"/><rect x="13" y="7.5" width="5.5" height="4" rx="1"/>"#

    static func image(_ body: String, size: CGFloat, color: String = "white") -> NSImage? {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke=""# + color + #"" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">"# + body + "</svg>"
        let image = NSImage(data: Data(svg.utf8))
        image?.size = NSSize(width: size, height: size)
        return image
    }
}

// MARK: - Ghost buttons (shown on hover)

// Shows an icon. With `doubleAction`, a single click waits out the
// double-click interval so a double-click doesn't fire the single-click action first. A triple-click
// fires `doubleAction` then `tripleAction`.
final class GhostButton: NSView {
    var icon: String { didSet { needsDisplay = true } }
    var isOn = false { didSet { needsDisplay = true } }  // toggles: yellow icon while on
    let action: (GhostButton) -> Void
    var doubleAction: ((GhostButton) -> Void)?
    var tripleAction: ((GhostButton) -> Void)?
    private var pendingClick: DispatchWorkItem?

    init(icon: String, tooltip: String, action: @escaping (GhostButton) -> Void) {
        self.icon = icon
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

        let side: CGFloat = 18
        Icon.image(icon, size: side, color: isOn ? "#FFC21A" : "white")?.draw(
            in: NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side),
            from: .zero, operation: .sourceOver, fraction: 1)
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
    // Overlapping flashes (double- then triple-click) restore to the pre-flash icon, not each other's.
    private var flashCount = 0
    private var restingIcon = ""

    func flash(_ temporary: String) {
        if flashCount == 0 { restingIcon = icon }
        flashCount += 1
        icon = temporary
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.flashCount -= 1
            if self.flashCount == 0 { self.icon = self.restingIcon }
        }
    }
}

// Saved window frames (the small-mode button), kept across launches.
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

// The pin button: show on every desktop (Space) instead of following the active one. Kept across launches.
enum Pinned {
    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: "pinned") }
        set { UserDefaults.standard.set(newValue, forKey: "pinned") }
    }

    static var behavior: NSWindow.CollectionBehavior {
        isOn ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
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
        // Something outside the app may have written a different-shaped image: fit the frame to it.
        return (image, gif, reshaped(frame, for: image))
    }
}

// MARK: - Window frames

// Natural size (pixels / screen scale), capped at 80% of the screen with the mouse, centred on it.
func centredFrame(for image: NSImage) -> NSRect {
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

    return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                  width: size.width, height: size.height)
}

// Which edges of its screen's visible area a frame hugs (within edgeSnap, or past them):
// x is -1 left / 1 right, y is -1 bottom / 1 top, 0 for neither — or both, as with big mode's full width.
// Two anchored edges pin a corner, one pins that edge (centred along it), none keeps the centre.
struct Anchor {
    var x = 0, y = 0

    init(_ frame: NSRect) {
        let mid = NSPoint(x: frame.midX, y: frame.midY)
        guard let v = (NSScreen.screens.first { NSMouseInRect(mid, $0.frame, false) } ?? NSScreen.main)?
            .visibleFrame else { return }
        func side(_ low: Bool, _ high: Bool) -> Int { low == high ? 0 : low ? -1 : 1 }
        x = side(frame.minX - v.minX <= edgeSnap, v.maxX - frame.maxX <= edgeSnap)
        y = side(frame.minY - v.minY <= edgeSnap, v.maxY - frame.maxY <= edgeSnap)
    }

    // A frame of `size` with this anchor's edges where they are in `frame`.
    func place(_ size: NSSize, from frame: NSRect) -> NSRect {
        func origin(_ side: Int, _ min: CGFloat, _ max: CGFloat, _ length: CGFloat) -> CGFloat {
            side < 0 ? min : side > 0 ? max - length : (min + max - length) / 2
        }
        return NSRect(x: origin(x, frame.minX, frame.maxX, size.width),
                      y: origin(y, frame.minY, frame.maxY, size.height),
                      width: size.width, height: size.height)
    }
}

// Same area as `frame`, reshaped to the image's aspect ratio, anchored to the edges it hugs.
func reshaped(_ frame: NSRect, for image: NSImage) -> NSRect {
    let a = image.size.width / image.size.height
    let w = (frame.width * frame.height * a).squareRoot()
    return Anchor(frame).place(NSSize(width: w, height: w / a), from: frame)
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var current: (image: NSImage, gif: Data?)?  // what the window shows, for Cmd+C
    var pinButton: GhostButton?

    // MARK: Modes (the hover buttons, and floater:// URLs for scripts and agents)

    // Big mode: as large as fits the screen (keeping aspect, bigMargin clear of the edges), centred.
    func bigFrame(for w: NSWindow) -> NSRect? {
        guard let screen = w.screen ?? NSScreen.main else { return nil }
        let aspect = w.frame.width / w.frame.height
        let area = screen.visibleFrame.insetBy(dx: bigMargin, dy: bigMargin)
        let bw = min(area.width, area.height * aspect), bh = bw / aspect
        return NSRect(x: area.midX - bw / 2, y: area.midY - bh / 2, width: bw, height: bh)
    }

    func bigMode() {
        guard let w = window, let frame = bigFrame(for: w) else { return }
        w.setFrame(frame, display: true, animate: true)
    }

    // Small mode: the saved frame, or by default small in the top-right corner (longer side
    // smallFraction of the screen's longer side). The button's double-click saves, triple-click clears.
    // Saved as slot "B" (the `slotB` default), from when the buttons were labelled A and B.
    func smallMode() {
        guard let w = window, let screen = w.screen ?? NSScreen.main else { return }
        let aspect = w.frame.width / w.frame.height
        if let saved = Slots.load("B") {
            // Keep the saved width; fit the height to this image's aspect ratio, anchored to the
            // edges the saved frame hugs.
            let size = NSSize(width: saved.width, height: saved.width / aspect)
            w.setFrame(Anchor(saved).place(size, from: saved), display: true, animate: true)
            return
        }
        let area = screen.visibleFrame.insetBy(dx: bigMargin, dy: bigMargin)
        let long = smallFraction * max(screen.visibleFrame.width, screen.visibleFrame.height)
        let sw = aspect >= 1 ? long : long * aspect, sh = sw / aspect
        w.setFrame(NSRect(x: area.maxX - sw, y: area.maxY - sh, width: sw, height: sh),
                   display: true, animate: true)
    }

    // Big mode if it isn't already (within a couple of points), else small mode.
    func toggleMode() {
        guard let w = window, let big = bigFrame(for: w) else { return }
        let f = w.frame
        let isBig = abs(f.minX - big.minX) < 2 && abs(f.minY - big.minY) < 2 && abs(f.width - big.width) < 2
        isBig ? smallMode() : bigMode()
    }

    func setPinned(_ on: Bool) {
        Pinned.isOn = on
        pinButton?.isOn = on
        window?.collectionBehavior = Pinned.behavior
    }

    // floater://big, small, toggle, pin, unpin. Acts on the open window; a URL that launches
    // Floater acts on whatever it opened with.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "floater" {
            switch url.host {
            case "big": bigMode()
            case "small": smallMode()
            case "toggle": toggleMode()
            case "pin": setPinned(true)
            case "unpin": setPinned(false)
            default: NSSound.beep()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        closeOtherInstances()
        setupMenu()
        if CommandLine.arguments.contains("--restore"), let state = SavedState.load() {
            // Scripted relaunch: show the image without taking focus from what the user is doing.
            show(image: state.image, gif: state.gif, frame: state.frame, activate: false)
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
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(copyImage(_:)), keyEquivalent: "c").target = self
        editMenu.addItem(withTitle: "Paste", action: #selector(pasteImage(_:)), keyEquivalent: "v").target = self
        editItem.submenu = editMenu
        NSApp.mainMenu = main
    }

    // Cmd+C on the focused window: copy the image (GIFs keep their animation).
    @objc func copyImage(_ sender: Any?) {
        guard let (image, gif) = current else { return }
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
    }

    // Cmd+V on the focused window: replace the image with the clipboard's, keeping the window's
    // centre and area. Beeps if there's no image on the clipboard.
    @objc func pasteImage(_ sender: Any?) {
        guard let (image, gif) = clipboardImage() else { NSSound.beep(); return }
        guard let w = window else { return showClipboard() }
        show(image: image, gif: gif, frame: reshaped(w.frame, for: image))
    }

    func clipboardImage() -> (image: NSImage, gif: Data?)? {
        let gif = pasteboardGIF(.general)
        guard let image = gif.flatMap(NSImage.init(data:)) ?? NSImage(pasteboard: .general), image.isValid
        else { return nil }
        return (image, gif)
    }

    func showClipboard() {
        guard let (image, gif) = clipboardImage() else {
            // No image on the clipboard: keep what's showing, else bring back the last image,
            // else start with a random photo.
            if window != nil { return }
            if let state = SavedState.load() { return show(image: state.image, gif: state.gif, frame: state.frame) }
            RandomPhoto.fetch { [weak self] photo in
                guard let self, self.window == nil else { return }
                guard let photo else {
                    self.notify("No image on clipboard")
                    NSApp.terminate(nil)
                    return
                }
                self.show(image: photo, gif: nil, frame: centredFrame(for: photo))
            }
            return
        }
        show(image: image, gif: gif, frame: centredFrame(for: image))
    }

    func show(image: NSImage, gif: Data?, frame: NSRect, activate: Bool = true) {
        window?.close()
        SavedState.save(image: image, gif: gif)
        SavedState.save(frame: frame)

        let size = frame.size
        let aspect = size.width / size.height
        let w = FloatWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .floating
        w.collectionBehavior = Pinned.behavior
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isReleasedWhenClosed = false

        let content = ImageView(image: image)
        content.onDoubleClick = { [weak self] in self?.toggleMode() }
        content.frame = NSRect(origin: .zero, size: size)
        content.autoresizingMask = [.width, .height]

        // Added before the buttons so the buttons win where they overlap.
        for corner in Corner.allCases {
            let side = hotCornerSize
            let handle = ResizeHandle(aspect: aspect, corner: corner)
            handle.frame = NSRect(x: corner.isRight ? size.width - side : 0,
                                  y: corner.isTop ? size.height - side : 0,
                                  width: side, height: side)
            handle.autoresizingMask = [corner.isRight ? .minXMargin : .maxXMargin,
                                       corner.isTop ? .minYMargin : .maxYMargin]
            content.addSubview(handle)
        }

        let close = GhostButton(icon: Icon.x, tooltip: "Close Floater (same as ⌘Q)") { _ in NSApp.terminate(nil) }
        let pin = GhostButton(icon: Icon.pin, tooltip: "Pin: show on every desktop, not just this one. Click again to unpin.") { [weak self] _ in
            self?.setPinned(!Pinned.isOn)
        }
        pin.isOn = Pinned.isOn
        pinButton = pin
        let big = GhostButton(icon: Icon.big, tooltip: """
            Big mode: as large as fits the screen, centred.
            Double-click the image to toggle between big and small mode.
            """) { [weak self] _ in
            self?.bigMode()
        }
        let small = GhostButton(icon: Icon.small, tooltip: """
            Small mode: snap to your small-mode spot (by default, small in the top-right corner).
            Double-click: save the current position and size as your small-mode spot.
            Triple-click: reset it to the default.
            Double-click the image to toggle between big and small mode.
            """) { [weak self] _ in
            self?.smallMode()
        }
        small.doubleAction = { [weak w] b in
            guard let w else { return }
            Slots.save("B", frame: w.frame)
            b.flash(Icon.check)
        }
        small.tripleAction = { b in
            Slots.clear("B")
            b.flash(Icon.check)
        }
        var buttons = [close, pin, small, big]
        if content.isAnimated {
            let play = GhostButton(icon: Icon.pause, tooltip: "Pause / play the GIF") { [weak content] b in
                guard let content else { return }
                content.isPaused.toggle()
                b.icon = content.isPaused ? Icon.play : Icon.pause
            }
            buttons.insert(play, at: 2)
        }
        // Right-to-left from the top-right corner: big, small, play/pause (GIFs only), pin, close.
        for (i, button) in buttons.enumerated() {
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
        if activate {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            w.orderFrontRegardless()
        }
        window = w
        current = (image, gif)
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
// Dark appearance so tooltips are light text on dark (Floater has no other visible chrome), and a short
// tooltip delay (ms; the system default is about a second).
app.appearance = NSAppearance(named: .darkAqua)
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 150])
let delegate = AppDelegate()
app.delegate = delegate
app.run()
