// Renders SVG files to square PNGs with AppKit, the same way Floater draws its icons.
// Usage: swift rasterize.swift SIZE IN.svg OUT.png [IN.svg OUT.png ...]
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3, args.count % 2 == 1, let size = Int(args[0]) else {
    FileHandle.standardError.write("usage: swift rasterize.swift SIZE IN.svg OUT.png ...\n".data(using: .utf8)!)
    exit(2)
}

for i in stride(from: 1, to: args.count, by: 2) {
    guard let image = NSImage(contentsOfFile: args[i]),
          let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("can't render \(args[i])") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[i + 1]))
}
