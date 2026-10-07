import AppKit
import WebKit

// Renders the README art from scripts/readme-art/art.html into docs/.
// Run from the repository root: swift scripts/make-readme-art.swift
// The demo GIF needs ffmpeg on the PATH.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let page = root.appendingPathComponent("scripts/readme-art/art.html")
let docs = root.appendingPathComponent("docs")

@MainActor
final class Renderer: NSObject, WKNavigationDelegate {
    private let window: NSWindow
    private let web: WKWebView
    private var loaded: CheckedContinuation<Void, Never>?

    init(size: CGSize) {
        web = WKWebView(frame: CGRect(origin: .zero, size: size))
        window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: size.width, height: size.height), styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.contentView = web
        window.orderFrontRegardless()
        web.navigationDelegate = self
    }

    func load(_ mode: String) async {
        let url = URL(string: page.absoluteString + "#" + mode)!
        web.loadFileURL(url, allowingReadAccessTo: page.deletingLastPathComponent())
        await withCheckedContinuation { loaded = $0 }
        try? await Task.sleep(for: .milliseconds(300))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            loaded?.resume()
            loaded = nil
        }
    }

    func run(_ script: String) async {
        _ = try? await web.evaluateJavaScript(script)
    }

    func snapshot(to url: URL, scale: CGFloat) async throws {
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(web.bounds.width * scale) / Double(window.backingScaleFactor))
        let image = try await web.takeSnapshot(configuration: configuration)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}

@MainActor
func still(_ mode: String, size: CGSize) async throws {
    let renderer = Renderer(size: size)
    await renderer.load(mode)
    try await renderer.snapshot(to: docs.appendingPathComponent("\(mode).png"), scale: 2)
    print("Wrote docs/\(mode).png")
}

@MainActor
func demo(_ theme: String) async throws {
    let frames = FileManager.default.temporaryDirectory.appendingPathComponent("clipline-demo-\(theme)", isDirectory: true)
    try? FileManager.default.removeItem(at: frames)
    try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

    let renderer = Renderer(size: CGSize(width: 960, height: 320))
    await renderer.load("demo-\(theme)")
    let fps = 20.0
    let duration = 9.8
    for index in 0..<Int(duration * fps) {
        await renderer.run("renderDemo(\(Double(index) / fps))")
        try await renderer.snapshot(to: frames.appendingPathComponent(String(format: "frame%04d.png", index)), scale: 2)
    }

    let output = docs.appendingPathComponent("demo-\(theme).gif")
    let ffmpeg = Process()
    ffmpeg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    ffmpeg.arguments = [
        "ffmpeg", "-v", "error", "-y", "-framerate", "\(Int(fps))",
        "-i", frames.appendingPathComponent("frame%04d.png").path,
        "-vf", "scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle",
        "-loop", "0", output.path
    ]
    try ffmpeg.run()
    ffmpeg.waitUntilExit()
    try? FileManager.default.removeItem(at: frames)
    print("Wrote docs/demo-\(theme).gif")
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    do {
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        for theme in ["light", "dark"] {
            try await still("hero-\(theme)", size: CGSize(width: 1200, height: 580))
            try await still("bento-\(theme)", size: CGSize(width: 1200, height: 560))
            try await demo(theme)
        }
    } catch {
        print("Failed: \(error)")
        exit(1)
    }
    exit(0)
}
app.run()
