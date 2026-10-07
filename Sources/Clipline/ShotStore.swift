import AppKit
import ImageIO
import Vision

@MainActor
final class ShotStore: ObservableObject {
    @Published private(set) var shots: [Shot] = []

    let folder: URL
    private let stateURL: URL
    private var thumbnails: [URL: NSImage] = [:]
    private var timer: Timer?

    static let expiryChoices = [1, 24, 168, 0]

    var expiryHours: Int {
        get { UserDefaults.standard.object(forKey: "expiryHours") as? Int ?? 24 }
        set {
            UserDefaults.standard.set(newValue, forKey: "expiryHours")
            expire()
        }
    }

    init() {
        let fm = FileManager.default
        folder = fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Clipline", isDirectory: true)
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipline", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        stateURL = support.appendingPathComponent("line.json")

        load()
        reconcile()
        expire()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconcile()
                self?.expire()
            }
        }
    }

    func add(_ url: URL) {
        guard !shots.contains(where: { $0.url == url }) else { return }
        shots.append(Shot(url: url, added: Date(), pinned: false))
        arrange()
        save()
        recognizeText(in: url)
    }

    func thumbnail(for shot: Shot) -> NSImage? {
        if let cached = thumbnails[shot.url] { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 520
        ]
        guard let source = CGImageSourceCreateWithURL(shot.url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails[shot.url] = image
        return image
    }

    func copyImage(_ shot: Shot) {
        guard let image = NSImage(contentsOf: shot.url) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([image])
    }

    func copyText(_ shot: Shot) -> Bool {
        guard let text = shots.first(where: { $0.id == shot.id })?.text, !text.isEmpty else { return false }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        return true
    }

    func togglePin(_ shot: Shot) {
        guard let index = shots.firstIndex(where: { $0.id == shot.id }) else { return }
        shots[index].pinned.toggle()
        arrange()
        save()
    }

    func open(_ shot: Shot) {
        let workspace = NSWorkspace.shared
        if let preview = workspace.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            workspace.open([shot.url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(shot.url)
        }
    }

    func reveal(_ shot: Shot) {
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }

    func trash(_ shot: Shot) {
        try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
        reconcile()
    }

    func clearUnpinned() {
        for shot in shots where !shot.pinned {
            try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
        }
        reconcile()
    }

    func reconcile() {
        let fm = FileManager.default
        let kept = shots.filter { fm.fileExists(atPath: $0.url.path) }
        guard kept.count != shots.count else { return }
        shots = kept
        let live = Set(kept.map(\.url))
        thumbnails = thumbnails.filter { live.contains($0.key) }
        save()
    }

    func expire() {
        guard expiryHours > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(expiryHours) * 3600)
        let stale = shots.filter { !$0.pinned && $0.added < cutoff }
        guard !stale.isEmpty else { return }
        for shot in stale {
            try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
        }
        reconcile()
    }

    private func arrange() {
        shots.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.added > b.added
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let saved = try? JSONDecoder().decode([Shot].self, from: data)
        else { return }
        shots = saved
        arrange()
        for shot in shots where shot.text == nil {
            recognizeText(in: shot.url)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(shots) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private nonisolated static func readText(in url: URL, level: VNRequestTextRecognitionLevel) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(url: url).perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func recognizeText(in url: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let text = Self.readText(in: url, level: .accurate) ?? Self.readText(in: url, level: .fast) ?? ""
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let index = self.shots.firstIndex(where: { $0.url == url }) else { return }
                    self.shots[index].text = text
                    self.save()
                }
            }
        }
    }
}
